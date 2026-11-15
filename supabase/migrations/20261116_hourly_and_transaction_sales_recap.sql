create or replace function public.get_hourly_sales_recap(p_business_date date)
returns table (
  period_start timestamp without time zone,
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
      date_trunc('hour', o.created_at at time zone 'Asia/Jakarta') as period_start,
      o.total_revenue,
      o.payment_method
    from public.orders as o
    where o.business_date = p_business_date
      and o.payment_status = 'paid'
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
      p.period_start,
      avg(r.rating) as average_rating,
      count(*) as review_count
    from paid_orders as p
    join public.reviews as r on r.order_id = p.id
    group by p.period_start
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
  order by o.period_start;
$$;

create or replace function public.get_transaction_sales_recap(p_business_date date)
returns table (
  order_id uuid,
  queue_number integer,
  created_at timestamptz,
  payment_method text,
  revenue numeric,
  estimated_cogs numeric,
  portion_count bigint,
  review_rating integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.queue_number,
    o.created_at,
    o.payment_method,
    o.total_revenue,
    coalesce(sum(i.estimated_cogs), 0),
    coalesce(sum(i.qty), 0)::bigint,
    max(r.rating)
  from public.orders as o
  left join public.order_items as i on i.order_id = o.id
  left join public.reviews as r on r.order_id = o.id
  where o.business_date = p_business_date
    and o.payment_status = 'paid'
  group by o.id
  order by o.created_at, o.queue_number;
$$;

revoke all on function public.get_hourly_sales_recap(date) from public, anon;
revoke all on function public.get_transaction_sales_recap(date) from public, anon;
grant execute on function public.get_hourly_sales_recap(date) to authenticated;
grant execute on function public.get_transaction_sales_recap(date) to authenticated;

notify pgrst, 'reload schema';
