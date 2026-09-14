-- Optional demo data (run AFTER creating a driver account via the app)
-- Replace :driver_id with the auth user UUID from Authentication → Users

-- Example (uncomment and paste your driver UUID):
/*
do $$
declare
  d uuid := 'PASTE_DRIVER_UUID_HERE';
  t1 uuid := '11111111-1111-1111-1111-111111111111';
  t2 uuid := '22222222-2222-2222-2222-222222222222';
  shift_id uuid;
  p1 uuid;
begin
  update public.drivers
  set
    full_name = 'Ramon Reyes',
    toda_number = 'SSLTODA No. 00876',
    plate_number = '123ABC',
    years_of_service = 5,
    assigned_terminal_id = t1,
    current_terminal_id = t1,
    mobile_number = coalesce(mobile_number, '09171234567')
  where id = d;

  insert into public.driver_schedules (driver_id, shift, day_of_week, start_time, end_time, terminal_id)
  select d, s.shift, dow, s.start_time, s.end_time, t1
  from generate_series(1, 5) as dow, -- Mon–Fri
  (values
    ('morning'::public.shift_type, '06:00'::time, '14:00'::time),
    ('afternoon'::public.shift_type, '14:00'::time, '22:00'::time)
  ) as s(shift, start_time, end_time)
  on conflict do nothing;

  insert into public.driver_shifts (driver_id, terminal_id, shift_date, shift, start_at, end_at)
  values (
    d, t1, current_date, 'morning',
    (current_date + time '06:00') at time zone 'Asia/Manila',
    (current_date + time '14:00') at time zone 'Asia/Manila'
  )
  on conflict (driver_id, shift_date, shift) do update
    set terminal_id = excluded.terminal_id
  returning id into shift_id;

  insert into public.passengers (id, full_name, mobile_number)
  values
    (gen_random_uuid(), 'Maria Santos', '09180001111'),
    (gen_random_uuid(), 'Juan Dela Cruz', '09180002222'),
    (gen_random_uuid(), 'Ana Reyes', '09180003333')
  returning id into p1;

  insert into public.bookings (
    driver_id, shift_id, passenger_name, passenger_mobile, passenger_count,
    pickup_terminal_id, dropoff_terminal_id, scheduled_at, status,
    notes, estimated_fare
  ) values
    (d, shift_id, 'Maria Santos', '09180001111', 2, t1, t2,
     (current_date + time '08:30') at time zone 'Asia/Manila', 'upcoming',
     'Please prepare exact fare.', 50),
    (d, shift_id, 'Juan Dela Cruz', '09180002222', 1, t1, t2,
     (current_date + time '09:15') at time zone 'Asia/Manila', 'upcoming',
     null, 50),
    (d, shift_id, 'Ana Reyes', '09180003333', 3, t2, t1,
     (current_date + time '07:00') at time zone 'Asia/Manila', 'completed',
     null, 50);

  update public.bookings
  set actual_fare = 50, completed_at = scheduled_at + interval '25 minutes'
  where driver_id = d and status = 'completed';

  insert into public.reviews (driver_id, passenger_name, rating, comment, created_at)
  values
    (d, 'Maria Santos', 5, 'Very safe and smooth ride!', now() - interval '2 days'),
    (d, 'Juan Dela Cruz', 5, 'On time and courteous.', now() - interval '5 days'),
    (d, 'Ana Reyes', 4, 'Good trip overall.', now() - interval '10 days');
end $$;
*/
