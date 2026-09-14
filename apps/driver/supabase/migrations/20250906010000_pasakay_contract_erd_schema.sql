-- PASAKAY contract-aligned schema (mirrors Supabase migration pasakay_contract_erd_schema)
-- Sources: CONTRACT (1).pdf §3 + PASAKAY Relevant Information.pdf (terminals, shifts, privacy fields)
-- Explicitly OUT OF SCOPE per Terms: online booking, dispatch, GPS, fare, digital payment

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('commuter', 'driver');
exception when duplicate_object then null; end $$;

create table if not exists public.terminals (
  terminal_id uuid primary key default gen_random_uuid(),
  terminal_name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.shifts (
  shift_id uuid primary key default gen_random_uuid(),
  shift_start_time time not null,
  shift_end_time time not null,
  label text not null,
  created_at timestamptz not null default now(),
  unique (shift_start_time, shift_end_time)
);

create table if not exists public.commuters (
  commuter_id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  contact_number text not null,
  email_address text,
  username text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drivers (
  driver_id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  contact_number text not null,
  driver_license_number text not null,
  plate_number text not null,
  toda_number text,
  username text not null unique,
  terminal_id uuid not null references public.terminals (terminal_id),
  shift_id uuid not null references public.shifts (shift_id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reviews (
  review_id uuid primary key default gen_random_uuid(),
  commuter_id uuid not null references public.commuters (commuter_id) on delete cascade,
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  content text,
  date_created timestamptz not null default now()
);

create table if not exists public.notifications (
  notification_id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null,
  recipient_type public.user_role not null,
  message_content text not null,
  date_sent timestamptz not null default now(),
  is_read boolean not null default false
);

create table if not exists public.device_logs (
  log_id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  user_type public.user_role not null,
  device_model text,
  os_version text,
  app_version text,
  access_datetime timestamptz not null default now(),
  crash_error_log text
);
