-- Realtime filters on UPDATE/DELETE need replica identity; keep tables in publication.
alter table public.ride_requests replica identity full;
alter table public.bookings replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.ride_requests;
  exception
    when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.bookings;
  exception
    when duplicate_object then null;
  end;
end $$;
