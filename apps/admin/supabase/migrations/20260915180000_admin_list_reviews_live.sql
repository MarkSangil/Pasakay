-- Remove demo seed reviews that are not tied to bookings.
delete from public.review_reports
where review_id in (select review_id from public.reviews where booking_id is null);

delete from public.reviews
where booking_id is null;

create or replace function public.admin_list_reviews()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  return coalesce((
    select jsonb_agg(row_to_json(x)::jsonb order by x.date_created desc)
    from (
      select
        r.review_id,
        r.commuter_id,
        r.driver_id,
        r.booking_id,
        r.rating,
        r.content,
        r.date_created,
        r.is_hidden,
        r.moderation_note,
        c.full_name as commuter_name,
        d.full_name as driver_name,
        d.plate_number as driver_plate
      from public.reviews r
      left join public.commuters c on c.commuter_id = r.commuter_id
      left join public.drivers d on d.driver_id = r.driver_id
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_reviews() from public;
grant execute on function public.admin_list_reviews() to authenticated;
