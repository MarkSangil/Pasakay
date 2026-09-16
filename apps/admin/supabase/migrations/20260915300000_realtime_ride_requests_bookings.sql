-- Enable live UI refresh when drivers accept/reject requests or bookings change.
alter publication supabase_realtime add table public.ride_requests;
alter publication supabase_realtime add table public.bookings;
