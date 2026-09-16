-- Auto-dispatch FCM when a notifications row is inserted.
-- Uses pg_net + vault secret `notification_push_webhook_secret`.
-- Edge Functions must also have secret NOTIFICATION_PUSH_SECRET = same value.
--
-- One-time secret bootstrap (if missing):
--   select vault.create_secret('<random-hex>', 'notification_push_webhook_secret');

create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_notification_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net, vault
as $$
declare
  v_secret text;
  v_url text;
  v_headers jsonb;
  v_body jsonb;
begin
  if new.recipient_type is distinct from 'driver'
     and new.recipient_type is distinct from 'commuter' then
    return new;
  end if;

  select ds.decrypted_secret
    into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'notification_push_webhook_secret'
  limit 1;

  if v_secret is null or length(trim(v_secret)) = 0 then
    raise warning 'notification_push_webhook_secret missing in vault; push skipped';
    return new;
  end if;

  if new.recipient_type = 'driver' then
    v_url := 'https://musogdwaxdyiatmnitkg.supabase.co/functions/v1/send-driver-push';
  else
    v_url := 'https://musogdwaxdyiatmnitkg.supabase.co/functions/v1/send-passenger-push';
  end if;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || v_secret
  );

  v_body := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', to_jsonb(new)
  );

  perform net.http_post(
    url := v_url,
    headers := v_headers,
    body := v_body,
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'dispatch_notification_push failed: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_notifications_dispatch_push on public.notifications;
create trigger trg_notifications_dispatch_push
  after insert on public.notifications
  for each row
  execute function public.dispatch_notification_push();

comment on function public.dispatch_notification_push() is
  'After INSERT on notifications, async HTTP POST to send-driver-push / send-passenger-push via pg_net.';
