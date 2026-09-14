-- Pasakay Driver App schema
-- Run this in the Supabase SQL Editor (Dashboard → SQL → New query)

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.shift_type as enum ('morning', 'afternoon', 'evening');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.booking_status as enum ('upcoming', 'ongoing', 'completed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_event as enum (
    'new_booking',
    'booking_cancelled',
    'trip_reminder',
    'review_received',
    'shift_starting',
    'system'
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Terminals
-- ---------------------------------------------------------------------------
create table if not exists public.terminals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  city text not null default 'Antipolo City',
  is_main boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Drivers (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table if not exists public.drivers (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  mobile_number text not null unique,
  email text not null unique,
  toda_number text,
  license_number text,
  plate_number text,
  years_of_service int not null default 0,
  assigned_terminal_id uuid references public.terminals (id),
  current_terminal_id uuid references public.terminals (id),
  avatar_url text,
  average_rating numeric(3,2) not null default 0,
  review_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists drivers_mobile_idx on public.drivers (mobile_number);
create index if not exists drivers_assigned_terminal_idx on public.drivers (assigned_terminal_id);

-- ---------------------------------------------------------------------------
-- Operating schedules (availability is derived from these — no manual toggle)
-- ---------------------------------------------------------------------------
create table if not exists public.driver_schedules (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  shift public.shift_type not null,
  day_of_week smallint not null check (day_of_week between 0 and 6), -- 0=Sun
  start_time time not null,
  end_time time not null,
  terminal_id uuid references public.terminals (id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (driver_id, shift, day_of_week)
);

-- ---------------------------------------------------------------------------
-- Shift instances (concrete date windows shown in Bookings This Shift)
-- ---------------------------------------------------------------------------
create table if not exists public.driver_shifts (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  terminal_id uuid not null references public.terminals (id),
  shift_date date not null,
  shift public.shift_type not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (driver_id, shift_date, shift)
);

create index if not exists driver_shifts_driver_date_idx
  on public.driver_shifts (driver_id, shift_date);

-- ---------------------------------------------------------------------------
-- Passengers (lightweight; full passenger app can expand later)
-- ---------------------------------------------------------------------------
create table if not exists public.passengers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  mobile_number text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Bookings
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  passenger_id uuid references public.passengers (id),
  shift_id uuid references public.driver_shifts (id),
  passenger_name text not null,
  passenger_mobile text,
  passenger_count int not null default 1 check (passenger_count > 0),
  pickup_terminal_id uuid not null references public.terminals (id),
  dropoff_terminal_id uuid not null references public.terminals (id),
  scheduled_at timestamptz not null,
  status public.booking_status not null default 'upcoming',
  trip_status_note text,
  notes text,
  estimated_fare numeric(10,2) not null default 0,
  actual_fare numeric(10,2),
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bookings_driver_status_idx
  on public.bookings (driver_id, status, scheduled_at);

-- ---------------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------------
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete set null,
  passenger_id uuid references public.passengers (id),
  passenger_name text not null,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

create index if not exists reviews_driver_idx on public.reviews (driver_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Device tokens (FCM / APNs) for push notifications
-- ---------------------------------------------------------------------------
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (driver_id, token)
);

-- ---------------------------------------------------------------------------
-- In-app notification feed
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (id) on delete cascade,
  event public.notification_event not null default 'system',
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_driver_unread_idx
  on public.notifications (driver_id, is_read, created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers / triggers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists drivers_set_updated_at on public.drivers;
create trigger drivers_set_updated_at
  before update on public.drivers
  for each row execute function public.set_updated_at();

drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function public.set_updated_at();

-- Keep average_rating / review_count in sync
create or replace function public.refresh_driver_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  target := coalesce(new.driver_id, old.driver_id);
  update public.drivers d
  set
    average_rating = coalesce((
      select round(avg(r.rating)::numeric, 2) from public.reviews r where r.driver_id = target
    ), 0),
    review_count = (
      select count(*) from public.reviews r where r.driver_id = target
    )
  where d.id = target;
  return coalesce(new, old);
end;
$$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_driver_rating();

-- Availability: true when now() falls inside an active schedule window (local PH time assumed by caller)
create or replace function public.is_driver_on_shift(p_driver_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.driver_schedules s
    where s.driver_id = p_driver_id
      and s.is_active = true
      and s.day_of_week = extract(dow from (now() at time zone 'Asia/Manila'))::int
      and (now() at time zone 'Asia/Manila')::time
          between s.start_time and s.end_time
  );
$$;

-- Auto-create driver profile row after signup (metadata from client)
create or replace function public.handle_new_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.drivers (
    id,
    full_name,
    mobile_number,
    email,
    toda_number,
    license_number,
    plate_number,
    assigned_terminal_id
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Driver'),
    coalesce(new.raw_user_meta_data->>'mobile_number', new.phone, new.email),
    coalesce(new.email, new.raw_user_meta_data->>'email'),
    new.raw_user_meta_data->>'toda_number',
    new.raw_user_meta_data->>'license_number',
    new.raw_user_meta_data->>'plate_number',
    nullif(new.raw_user_meta_data->>'assigned_terminal_id', '')::uuid
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_driver on auth.users;
create trigger on_auth_user_created_driver
  after insert on auth.users
  for each row execute function public.handle_new_driver();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.terminals enable row level security;
alter table public.drivers enable row level security;
alter table public.driver_schedules enable row level security;
alter table public.driver_shifts enable row level security;
alter table public.passengers enable row level security;
alter table public.bookings enable row level security;
alter table public.reviews enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;

-- Terminals: readable by authenticated drivers
drop policy if exists "terminals_select_authenticated" on public.terminals;
create policy "terminals_select_authenticated"
  on public.terminals for select
  to authenticated
  using (true);

-- Drivers: read/update own row
drop policy if exists "drivers_select_own" on public.drivers;
create policy "drivers_select_own"
  on public.drivers for select
  to authenticated
  using (id = auth.uid());

drop policy if exists "drivers_update_own" on public.drivers;
create policy "drivers_update_own"
  on public.drivers for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Schedules / shifts / bookings / reviews / tokens / notifications: own rows
drop policy if exists "schedules_own" on public.driver_schedules;
create policy "schedules_own"
  on public.driver_schedules for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "shifts_own" on public.driver_shifts;
create policy "shifts_own"
  on public.driver_shifts for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "bookings_own" on public.bookings;
create policy "bookings_own"
  on public.bookings for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "reviews_own_select" on public.reviews;
create policy "reviews_own_select"
  on public.reviews for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists "passengers_select_authenticated" on public.passengers;
create policy "passengers_select_authenticated"
  on public.passengers for select
  to authenticated
  using (true);

drop policy if exists "tokens_own" on public.device_tokens;
create policy "tokens_own"
  on public.device_tokens for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "notifications_own" on public.notifications;
create policy "notifications_own"
  on public.notifications for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime (online sync)
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.bookings;
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.reviews;
alter publication supabase_realtime add table public.drivers;

-- ---------------------------------------------------------------------------
-- Seed sample terminals (safe to re-run)
-- ---------------------------------------------------------------------------
insert into public.terminals (id, name, address, city, is_main)
values
  ('11111111-1111-1111-1111-111111111111', 'Camella Montego Terminal', 'Brgy. San Luis, Antipolo City', 'Antipolo City', false),
  ('22222222-2222-2222-2222-222222222222', 'Bayan Terminal (Main Terminal)', 'Brgy. San Luis, Antipolo City', 'Antipolo City', true)
on conflict (id) do nothing;
