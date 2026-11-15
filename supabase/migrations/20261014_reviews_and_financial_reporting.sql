create table if not exists public.ingredient_costs (
  ingredient_id text primary key references public.ingredients(id) on delete cascade,
  unit_cost integer not null default 0 check (unit_cost >= 0),
  updated_at timestamptz not null default now()
);

alter table public.ingredient_costs enable row level security;
drop policy if exists "owner reads ingredient costs" on public.ingredient_costs;
create policy "owner reads ingredient costs"
  on public.ingredient_costs for select to authenticated using (true);
revoke all on table public.ingredient_costs from anon, authenticated;
grant select on table public.ingredient_costs to authenticated;

insert into public.ingredient_costs (ingredient_id, unit_cost) values
  ('chicken_sm', 6500),
  ('chicken_md', 7800),
  ('chicken_lg', 9750),
  ('sauce_classic', 1000),
  ('sauce_lava', 1000),
  ('sauce_mushroom', 1100),
  ('sauce_thunder', 1100),
  ('rice', 1500),
  ('fries', 2500),
  ('packaging', 700)
on conflict (ingredient_id) do update
set unit_cost = excluded.unit_cost
where ingredient_costs.unit_cost = 0;

alter table public.order_items
  add column if not exists estimated_cogs numeric(12, 2) not null default 0
    check (estimated_cogs >= 0);

create or replace function public.snapshot_order_item_cogs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chicken_id text;
  v_sauce_id text;
  v_cost_count integer;
  v_unit_cost integer;
begin
  v_chicken_id := case new.size
    when 'small' then 'chicken_sm'
    when 'medium' then 'chicken_md'
    when 'large' then 'chicken_lg'
  end;
  v_sauce_id := case new.sauce_variant
    when 'classic_cheese' then 'sauce_classic'
    when 'hot_lava' then 'sauce_lava'
    when 'magic_mushroom' then 'sauce_mushroom'
    when 'black_thunder' then 'sauce_thunder'
  end;

  select count(*), coalesce(sum(unit_cost), 0)
    into v_cost_count, v_unit_cost
  from public.ingredient_costs
  where ingredient_id in (v_chicken_id, v_sauce_id, new.carb_type, 'packaging');

  if v_cost_count <> 4 then
    raise exception 'Biaya HPP bahan untuk menu ini belum lengkap.';
  end if;

  new.estimated_cogs := v_unit_cost * new.qty;
  return new;
end;
$$;

drop trigger if exists order_items_snapshot_cogs on public.order_items;
create trigger order_items_snapshot_cogs
before insert on public.order_items
for each row execute function public.snapshot_order_item_cogs();

update public.order_items as item
set estimated_cogs = item.qty * (
  select sum(cost.unit_cost)
  from public.ingredient_costs as cost
  where cost.ingredient_id in (
    case item.size
      when 'small' then 'chicken_sm'
      when 'medium' then 'chicken_md'
      when 'large' then 'chicken_lg'
    end,
    case item.sauce_variant
      when 'classic_cheese' then 'sauce_classic'
      when 'hot_lava' then 'sauce_lava'
      when 'magic_mushroom' then 'sauce_mushroom'
      when 'black_thunder' then 'sauce_thunder'
    end,
    item.carb_type,
    'packaging'
  )
)
where item.estimated_cogs = 0;

create or replace function public.set_ingredient_unit_cost(
  p_ingredient_id text,
  p_unit_cost integer
)
returns public.ingredients
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ingredient public.ingredients;
begin
  if p_unit_cost is null or p_unit_cost < 0 or p_unit_cost > 100000000 then
    raise exception 'Harga bahan tidak valid.';
  end if;

  update public.ingredient_costs
  set unit_cost = p_unit_cost, updated_at = now()
  where ingredient_id = p_ingredient_id;

  if not found then
    raise exception 'Bahan tidak ditemukan.';
  end if;

  select * into v_ingredient
  from public.ingredients
  where id = p_ingredient_id;

  return v_ingredient;
end;
$$;

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_name text not null default 'Pelanggan'
    check (char_length(customer_name) <= 30),
  rating integer not null check (rating between 1 and 5),
  comment text not null default ''
    check (char_length(comment) <= 240),
  created_at timestamptz not null default now(),
  unique (order_id)
);

create index if not exists reviews_created_at_idx
  on public.reviews (created_at desc);

alter table public.reviews enable row level security;
drop policy if exists "owner reads reviews" on public.reviews;
create policy "owner reads reviews"
  on public.reviews for select to authenticated using (true);

revoke all on table public.reviews from anon, authenticated;
grant select on table public.reviews to authenticated;

create or replace function public.submit_review(
  p_order_id uuid,
  p_customer_name text,
  p_rating integer,
  p_comment text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_review_id uuid;
begin
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Rating harus antara 1 dan 5.';
  end if;

  if not exists (
    select 1 from public.orders
    where id = p_order_id
      and status <> 'cancelled'
  ) then
    raise exception 'Ulasan hanya dapat dikirim untuk pesanan yang masih valid.';
  end if;

  insert into public.reviews (order_id, customer_name, rating, comment)
  values (
    p_order_id,
    coalesce(nullif(left(trim(coalesce(p_customer_name, '')), 30), ''), 'Pelanggan'),
    p_rating,
    left(trim(coalesce(p_comment, '')), 240)
  )
  returning id into v_review_id;

  return v_review_id;
end;
$$;

create or replace function public.get_public_reviews(p_limit integer default 50)
returns table (
  customer_name text,
  rating integer,
  comment text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.customer_name, r.rating, r.comment, r.created_at
  from public.reviews as r
  order by r.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

create or replace function public.get_review_summary()
returns table (
  average_rating numeric,
  review_count bigint,
  satisfied_percent integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(round(avg(rating), 1), 0),
    count(*),
    coalesce(round(100.0 * count(*) filter (where rating >= 4) / nullif(count(*), 0)), 0)::integer
  from public.reviews;
$$;

create or replace function public.get_sales_recap(
  p_start_date date,
  p_end_date date,
  p_period text
)
returns table (
  period_start date,
  revenue numeric,
  estimated_cogs numeric,
  transaction_count bigint,
  portion_count bigint,
  cash_revenue numeric,
  qris_revenue numeric,
  average_rating numeric,
  review_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with paid_orders as (
    select
      o.id,
      o.business_date,
      o.total_revenue,
      o.payment_method,
      date_trunc(
        case p_period when 'week' then 'week' when 'month' then 'month' else 'day' end,
        o.business_date::timestamp
      )::date as period_start
    from public.orders as o
    where o.payment_status = 'paid'
      and o.business_date between p_start_date and p_end_date
      and p_start_date <= p_end_date
      and p_period in ('day', 'week', 'month')
  ),
  order_totals as (
    select
      p.period_start,
      sum(p.total_revenue) as revenue,
      count(*) as transaction_count,
      sum(p.total_revenue) filter (where p.payment_method = 'cash') as cash_revenue,
      sum(p.total_revenue) filter (where p.payment_method = 'qris') as qris_revenue
    from paid_orders as p
    group by p.period_start
  ),
  item_totals as (
    select
      p.period_start,
      sum(i.estimated_cogs) as estimated_cogs,
      sum(i.qty) as portion_count
    from paid_orders as p
    join public.order_items as i on i.order_id = p.id
    group by p.period_start
  ),
  review_totals as (
    select
      date_trunc(
        case p_period when 'week' then 'week' when 'month' then 'month' else 'day' end,
        o.business_date::timestamp
      )::date as period_start,
      avg(r.rating) as average_rating,
      count(*) as review_count
    from public.reviews as r
    join public.orders as o on o.id = r.order_id
    where o.business_date between p_start_date and p_end_date
      and o.status <> 'cancelled'
      and p_start_date <= p_end_date
      and p_period in ('day', 'week', 'month')
    group by 1
  )
  select
    o.period_start,
    o.revenue,
    coalesce(i.estimated_cogs, 0),
    o.transaction_count,
    coalesce(i.portion_count, 0),
    coalesce(o.cash_revenue, 0),
    coalesce(o.qris_revenue, 0),
    coalesce(r.average_rating, 0),
    coalesce(r.review_count, 0)
  from order_totals as o
  left join item_totals as i using (period_start)
  left join review_totals as r using (period_start)
  order by o.period_start desc;
$$;

revoke all on function public.snapshot_order_item_cogs() from public, anon, authenticated;
revoke all on function public.set_ingredient_unit_cost(text, integer) from public, anon;
revoke all on function public.submit_review(uuid, text, integer, text) from public;
revoke all on function public.get_public_reviews(integer) from public;
revoke all on function public.get_review_summary() from public;
revoke all on function public.get_sales_recap(date, date, text) from public, anon;

grant execute on function public.set_ingredient_unit_cost(text, integer) to authenticated;
grant execute on function public.submit_review(uuid, text, integer, text) to anon, authenticated;
grant execute on function public.get_public_reviews(integer) to anon, authenticated;
grant execute on function public.get_review_summary() to anon, authenticated;
grant execute on function public.get_sales_recap(date, date, text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'reviews'
  ) then
    alter publication supabase_realtime add table public.reviews;
  end if;
end;
$$;

notify pgrst, 'reload schema';
