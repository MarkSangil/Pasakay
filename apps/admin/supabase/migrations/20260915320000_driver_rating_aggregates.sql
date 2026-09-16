-- Persist driver rating aggregates (missing from live ERD schema).
alter table public.drivers
  add column if not exists average_rating numeric(3, 2) not null default 0,
  add column if not exists review_count int not null default 0;

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
  if target is null then
    return coalesce(new, old);
  end if;

  update public.drivers d
  set
    average_rating = coalesce((
      select round(avg(r.rating)::numeric, 2)
      from public.reviews r
      where r.driver_id = target
        and coalesce(r.is_hidden, false) = false
    ), 0),
    review_count = (
      select count(*)::int
      from public.reviews r
      where r.driver_id = target
        and coalesce(r.is_hidden, false) = false
    ),
    updated_at = now()
  where d.driver_id = target;

  return coalesce(new, old);
end;
$$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_driver_rating();

-- Backfill from existing visible reviews.
update public.drivers d
set
  average_rating = coalesce(s.avg_rating, 0),
  review_count = coalesce(s.cnt, 0),
  updated_at = now()
from (
  select
    r.driver_id,
    round(avg(r.rating)::numeric, 2) as avg_rating,
    count(*)::int as cnt
  from public.reviews r
  where coalesce(r.is_hidden, false) = false
  group by r.driver_id
) s
where d.driver_id = s.driver_id;

-- Drivers with no visible reviews stay at 0.
update public.drivers d
set average_rating = 0, review_count = 0, updated_at = now()
where not exists (
  select 1
  from public.reviews r
  where r.driver_id = d.driver_id
    and coalesce(r.is_hidden, false) = false
)
and (d.average_rating is distinct from 0 or d.review_count is distinct from 0);
