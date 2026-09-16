-- Allow drivers to see name/contact for passengers they have a request or booking with.
-- Mirrors drivers_read_all for the passenger→driver contact path.
drop policy if exists "commuters_select_related_driver" on public.commuters;
create policy "commuters_select_related_driver"
  on public.commuters
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings b
      where b.commuter_id = commuters.commuter_id
        and b.driver_id = auth.uid()
    )
    or exists (
      select 1
      from public.ride_requests r
      where r.commuter_id = commuters.commuter_id
        and r.driver_id = auth.uid()
    )
  );
