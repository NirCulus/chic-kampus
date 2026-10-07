-- Schema dasar Chic Kampus: dapat membangun database lokal dari nol.
create extension if not exists pgcrypto;

create table if not exists public.ingredients (
  id text primary key,
  name text not null,
  stock integer not null default 0 check (stock >= 0),
  unit_type text not null,
  min_stock integer not null default 0 check (min_stock >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  queue_number integer not null check (queue_number > 0),
  business_date date not null default (timezone('Asia/Jakarta', now())::date),
  payment_method text not null check (payment_method in ('qris', 'cash')),
  payment_status text not null check (payment_status in ('waiting', 'paid', 'void')),
  status text not null check (status in ('waiting', 'processing', 'completed', 'cancelled')),
  total_revenue numeric(12, 2) not null default 0 check (total_revenue >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_date, queue_number)
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  size text not null check (size in ('small', 'medium', 'large')),
  sauce_variant text not null check (sauce_variant in ('classic_cheese', 'hot_lava', 'magic_mushroom', 'black_thunder')),
  carb_type text not null check (carb_type in ('rice', 'fries')),
  qty integer not null check (qty > 0),
  subtotal numeric(12, 2) not null check (subtotal >= 0)
);

create table if not exists public.stock_ledger (
  id uuid primary key default gen_random_uuid(),
  ingredient_id text not null references public.ingredients(id),
  order_id uuid references public.orders(id) on delete set null,
  change_type text not null check (change_type in ('sale', 'refund', 'adjustment')),
  quantity integer not null check (quantity <> 0),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists orders_business_date_idx on public.orders (business_date);
create index if not exists order_items_order_id_idx on public.order_items (order_id);
create index if not exists stock_ledger_ingredient_id_idx on public.stock_ledger (ingredient_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists ingredients_set_updated_at on public.ingredients;
create trigger ingredients_set_updated_at before update on public.ingredients for each row execute function public.set_updated_at();
drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at before update on public.orders for each row execute function public.set_updated_at();

insert into public.ingredients (id, name, stock, unit_type, min_stock) values
  ('chicken_sm', 'Ayam Small', 30, 'porsi', 5),
  ('chicken_md', 'Ayam Medium', 30, 'porsi', 5),
  ('chicken_lg', 'Ayam Large', 30, 'porsi', 5),
  ('sauce_classic', 'Classic Cheese Sauce', 30, 'porsi', 5),
  ('sauce_lava', 'Hot Lava Sauce', 30, 'porsi', 5),
  ('sauce_mushroom', 'Magic Mushroom Sauce', 30, 'porsi', 5),
  ('sauce_thunder', 'Black Thunder Sauce', 30, 'porsi', 5),
  ('rice', 'Nasi', 50, 'porsi', 10),
  ('fries', 'Kentang', 50, 'porsi', 10),
  ('packaging', 'Kemasan', 50, 'pcs', 5)
on conflict (id) do nothing;

create or replace function public.create_order(p_payment_method text, p_items jsonb)
returns table (order_id uuid, queue_number integer, order_status text, order_payment_status text, total_revenue numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_order_id uuid; v_queue_number integer;
  v_business_date date := timezone('Asia/Jakarta', now())::date;
  v_total numeric(12, 2) := 0; v_qty integer; v_size text; v_sauce text; v_carb text;
  v_price numeric(12, 2); v_chicken_id text; v_sauce_id text; v_ingredient_id text; v_stock integer; v_subtotal numeric(12, 2);
begin
  if p_payment_method not in ('qris', 'cash') or p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Pesanan atau metode pembayaran tidak valid.';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_business_date::text));
  select coalesce(max(o.queue_number), 0) + 1 into v_queue_number from public.orders o where o.business_date = v_business_date;
  insert into public.orders (queue_number, business_date, payment_method, payment_status, status, total_revenue)
  values (v_queue_number, v_business_date, p_payment_method,
    case when p_payment_method = 'qris' then 'paid' else 'waiting' end,
    case when p_payment_method = 'qris' then 'processing' else 'waiting' end, 0)
  returning id into v_order_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_size := v_item ->> 'size'; v_sauce := v_item ->> 'sauce_variant'; v_carb := v_item ->> 'carb_type'; v_qty := (v_item ->> 'qty')::integer;
    v_chicken_id := case v_size when 'small' then 'chicken_sm' when 'medium' then 'chicken_md' when 'large' then 'chicken_lg' end;
    v_sauce_id := case v_sauce when 'classic_cheese' then 'sauce_classic' when 'hot_lava' then 'sauce_lava' when 'magic_mushroom' then 'sauce_mushroom' when 'black_thunder' then 'sauce_thunder' end;
    v_price := case v_size when 'small' then 15000 when 'medium' then 17000 when 'large' then 22000 end;
    if v_qty is null or v_qty < 1 or v_chicken_id is null or v_sauce_id is null or v_price is null or v_carb not in ('rice', 'fries') then raise exception 'Konfigurasi menu tidak valid.'; end if;
    foreach v_ingredient_id in array array[v_chicken_id, v_sauce_id, v_carb, 'packaging'] loop
      select stock into v_stock from public.ingredients where id = v_ingredient_id for update;
      if not found or v_stock < v_qty then raise exception 'Stok % tidak mencukupi.', v_ingredient_id; end if;
    end loop;
    update public.ingredients set stock = stock - v_qty where id in (v_chicken_id, v_sauce_id, v_carb, 'packaging');
    insert into public.stock_ledger (ingredient_id, order_id, change_type, quantity, notes) values
      (v_chicken_id, v_order_id, 'sale', -v_qty, 'Pesanan baru'),
      (v_sauce_id, v_order_id, 'sale', -v_qty, 'Pesanan baru'),
      (v_carb, v_order_id, 'sale', -v_qty, 'Pesanan baru'),
      ('packaging', v_order_id, 'sale', -v_qty, 'Pesanan baru');
    v_subtotal := v_price * v_qty; v_total := v_total + v_subtotal;
    insert into public.order_items (order_id, size, sauce_variant, carb_type, qty, subtotal)
    values (v_order_id, v_size, v_sauce, v_carb, v_qty, v_subtotal);
  end loop;
  update public.orders set total_revenue = v_total where id = v_order_id;
  return query select o.id, o.queue_number, o.status, o.payment_status, o.total_revenue from public.orders o where o.id = v_order_id;
end;
$$;

create or replace function public.cancel_order(p_order_id uuid, p_notes text default 'Pesanan dibatalkan oleh owner.')
returns public.orders language plpgsql security definer set search_path = public as $$
declare v_order public.orders; v_item record; v_chicken_id text; v_sauce_id text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if v_order.status = 'cancelled' then raise exception 'Pesanan sudah dibatalkan.'; end if;
  for v_item in select * from public.order_items where order_id = p_order_id loop
    v_chicken_id := case v_item.size when 'small' then 'chicken_sm' when 'medium' then 'chicken_md' when 'large' then 'chicken_lg' end;
    v_sauce_id := case v_item.sauce_variant when 'classic_cheese' then 'sauce_classic' when 'hot_lava' then 'sauce_lava' when 'magic_mushroom' then 'sauce_mushroom' when 'black_thunder' then 'sauce_thunder' end;
    update public.ingredients set stock = stock + v_item.qty where id in (v_chicken_id, v_sauce_id, v_item.carb_type, 'packaging');
    insert into public.stock_ledger (ingredient_id, order_id, change_type, quantity, notes) values
      (v_chicken_id, p_order_id, 'refund', v_item.qty, p_notes),
      (v_sauce_id, p_order_id, 'refund', v_item.qty, p_notes),
      (v_item.carb_type, p_order_id, 'refund', v_item.qty, p_notes),
      ('packaging', p_order_id, 'refund', v_item.qty, p_notes);
  end loop;
  update public.orders set status = 'cancelled', payment_status = 'void' where id = p_order_id returning * into v_order;
  return v_order;
end;
$$;

create or replace function public.get_financial_report(p_start_date date, p_end_date date)
returns table (revenue numeric, transaction_count bigint, average_transaction numeric, cash_revenue numeric, qris_revenue numeric)
language sql security definer set search_path = public as $$
  select coalesce(sum(total_revenue), 0), count(*), coalesce(avg(total_revenue), 0),
    coalesce(sum(total_revenue) filter (where payment_method = 'cash'), 0),
    coalesce(sum(total_revenue) filter (where payment_method = 'qris'), 0)
  from public.orders where payment_status = 'paid' and business_date between p_start_date and p_end_date;
$$;

create or replace function public.get_product_analytics(p_start_date date, p_end_date date)
returns table (size text, sauce_variant text, carb_type text, total_qty bigint, total_sales numeric)
language sql security definer set search_path = public as $$
  select oi.size, oi.sauce_variant, oi.carb_type, sum(oi.qty), sum(oi.subtotal)
  from public.order_items oi join public.orders o on o.id = oi.order_id
  where o.payment_status = 'paid' and o.business_date between p_start_date and p_end_date
  group by oi.size, oi.sauce_variant, oi.carb_type order by sum(oi.subtotal) desc;
$$;