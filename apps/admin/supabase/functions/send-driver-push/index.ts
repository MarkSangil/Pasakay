// Supabase Edge Function: send FCM push to a driver's registered devices.
//
// Secrets required (Dashboard → Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT_JSON = full Firebase service account JSON
//   NOTIFICATION_PUSH_SECRET = shared secret used by the DB pg_net trigger
//
// Auth: Authorization Bearer must match SUPABASE_SERVICE_ROLE_KEY (auto)
//   or NOTIFICATION_PUSH_SECRET (DB webhook / pg_net).
//
// Manual test body:
//   { "driver_id": "<uuid>", "title": "Pasakay", "body": "Hello" }
// or
//   { "notification_id": "<uuid>" }
// or Supabase webhook payload with record.recipient_id / message_content

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const encoder = new TextEncoder();

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type PushBody = {
  driver_id?: string;
  title?: string;
  body?: string;
  notification_id?: string;
  type?: string;
  table?: string;
  record?: {
    notification_id?: string;
    recipient_id?: string;
    recipient_type?: string;
    message_content?: string;
    title?: string;
    event_type?: string;
    data?: Record<string, unknown>;
  };
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const webhookSecret = Deno.env.get("NOTIFICATION_PUSH_SECRET") ?? "";
  const authorized =
    (serviceKey.length > 0 && auth === `Bearer ${serviceKey}`) ||
    (webhookSecret.length > 0 && auth === `Bearer ${webhookSecret}`);
  if (!authorized) {
    return json({ error: "Unauthorized" }, 401);
  }
  if (!serviceKey) {
    return json({ error: "Missing SUPABASE_SERVICE_ROLE_KEY" }, 500);
  }

  const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!saRaw) {
    return json({
      error:
        "Missing FIREBASE_SERVICE_ACCOUNT_JSON secret. Add the Firebase service account JSON in Edge Function secrets.",
    }, 500);
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(saRaw) as ServiceAccount;
  } catch {
    return json({ error: "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON" }, 500);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    serviceKey,
  );

  let payload: PushBody;
  try {
    payload = await req.json() as PushBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Normalize Database Webhook payloads.
  let driverId = payload.driver_id ?? payload.record?.recipient_id;
  let title = payload.title ?? payload.record?.title ?? "Pasakay";
  let body = payload.body ?? payload.record?.message_content ?? "";
  let eventType = payload.record?.event_type ?? "";
  let extraData: Record<string, string> = {};
  const notificationId =
    payload.notification_id ?? payload.record?.notification_id;

  if (payload.record?.data && typeof payload.record.data === "object") {
    for (const [k, v] of Object.entries(payload.record.data)) {
      if (v != null) extraData[k] = String(v);
    }
  }

  if (payload.record?.recipient_type && payload.record.recipient_type !== "driver") {
    return json({ ok: true, skipped: "not a driver notification" });
  }

  if ((!driverId || !body) && notificationId) {
    const { data, error } = await supabase
      .from("notifications")
      .select("notification_id, recipient_id, recipient_type, message_content, title, event_type, data")
      .eq("notification_id", notificationId)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!data) return json({ error: "Notification not found" }, 404);
    if (data.recipient_type !== "driver") {
      return json({ ok: true, skipped: "not a driver notification" });
    }
    driverId = data.recipient_id as string;
    body = data.message_content as string;
    title = (data.title as string) || title;
    eventType = (data.event_type as string) || eventType;
    if (data.data && typeof data.data === "object") {
      for (const [k, v] of Object.entries(data.data as Record<string, unknown>)) {
        if (v != null) extraData[k] = String(v);
      }
    }
  }

  if (!driverId || !body) {
    return json({ error: "driver_id and body (or notification_id) are required" }, 400);
  }

  const { data: tokens, error: tokenError } = await supabase
    .from("device_tokens")
    .select("token, platform")
    .eq("driver_id", driverId);

  if (tokenError) return json({ error: tokenError.message }, 500);
  if (!tokens?.length) {
    return json({ ok: true, sent: 0, reason: "no device tokens" });
  }

  const accessToken = await getGoogleAccessToken(sa);
  const results: Array<{ token: string; ok: boolean; detail?: string }> = [];

  for (const row of tokens) {
    const result = await sendFcm({
      projectId: sa.project_id,
      accessToken,
      deviceToken: row.token as string,
      title,
      body,
          data: {
            notification_id: notificationId ?? "",
            driver_id: driverId,
            event_type: eventType,
            title,
            body,
            ...extraData,
          },
    });
    results.push({ token: row.token as string, ...result });

    // Drop invalid tokens so the next send stays clean.
    if (
      result.detail?.includes("UNREGISTERED") ||
      result.detail?.includes("INVALID_ARGUMENT")
    ) {
      await supabase
        .from("device_tokens")
        .delete()
        .eq("driver_id", driverId)
        .eq("token", row.token);
    }
  }

  return json({
    ok: true,
    sent: results.filter((r) => r.ok).length,
    failed: results.filter((r) => !r.ok).length,
    results,
  });
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(unsigned),
  );
  const jwt = `${unsigned}.${base64Url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`Google token error: ${JSON.stringify(data)}`);
  }
  return data.access_token as string;
}

async function sendFcm(args: {
  projectId: string;
  accessToken: string;
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
}): Promise<{ ok: boolean; detail?: string }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${args.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: args.deviceToken,
          notification: {
            title: args.title,
            body: args.body,
          },
          data: args.data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "pasakay_driver_alerts",
              icon: "ic_stat_pasakay",
              default_sound: true,
              notification_count: 1,
            },
          },
          apns: {
            headers: {
              "apns-priority": "10",
            },
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
    },
  );
  const text = await res.text();
  if (!res.ok) {
    return { ok: false, detail: text };
  }
  return { ok: true, detail: text };
}

function base64Url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string"
    ? encoder.encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
