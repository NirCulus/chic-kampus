-- Tahap 3.5. Jalankan setelah schema utama dan migrasi empat saus.
-- Kiosk: baca stok/menu dan create_order. Owner: session Supabase Auth.

alter table public.ingredients enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.stock_ledger enable row level security;

-- Hapus policy lama agar tidak ada akses permisif yang tertinggal dari prototype.
do $$
declare policy_record record;
begin
  for policy_record in
    select tablename, policyname from pg_policies
    where schemaname = 'public' and tablename in ('ingredients', 'orders', 'order_items', 'stock_ledger')
  loop
    execute format('drop policy %I on public.%I', policy_record.policyname, policy_record.tablename);
  end loop;
end;
$$;
create policy "kiosk reads ingredients" on public.ingredients for select to anon using (true);
create policy "owner reads ingredients" on public.ingredients for select to authenticated using (true);
create policy "owner reads orders" on public.orders for select to authenticated using (true);
create policy "owner reads order items" on public.order_items for select to authenticated using (true);
create policy "owner reads stock ledger" on public.stock_ledger for select to authenticated using (true);

revoke all on table public.ingredients, public.orders, public.order_items, public.stock_ledger from anon;
revoke all on table public.ingredients, public.orders, public.order_items, public.stock_ledger from authenticated;
grant select on table public.ingredients to anon;
grant select on table public.ingredients, public.orders, public.order_items, public.stock_ledger to authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;

create or replace function public.confirm_cash_payment(p_order_id uuid)
returns public.orders language plpgsql security definer set search_path = public as $$
declare v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if v_order.payment_method <> 'cash' then raise exception 'Pesanan ini bukan pembayaran tunai.'; end if;
  if v_order.payment_status <> 'waiting' then raise exception 'Pembayaran tunai sudah diproses.'; end if;
  update public.orders set payment_status = 'paid', status = 'processing' where id = p_order_id returning * into v_order;
  return v_order;
end;
$$;

create or replace function public.update_order_status(p_order_id uuid, p_status text)
returns public.orders language plpgsql security definer set search_path = public as $$
declare v_order public.orders;
begin
  if p_status not in ('processing', 'completed') then raise exception 'Status tidak valid.'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if v_order.status = 'cancelled' then raise exception 'Pesanan dibatalkan tidak dapat diubah.'; end if;
  if p_status = 'processing' and v_order.payment_status <> 'paid' then raise exception 'Pesanan belum lunas.'; end if;
  update public.orders set status = p_status where id = p_order_id returning * into v_order;
  return v_order;
end;
$$;

create or replace function public.adjust_stock(p_ingredient_id text, p_quantity integer, p_change_type text, p_notes text default null)
returns public.ingredients language plpgsql security definer set search_path = public as $$
declare v_ingredient public.ingredients;
begin
  if p_quantity = 0 then raise exception 'Jumlah perubahan stok tidak boleh nol.'; end if;
  if p_change_type not in ('adjustment', 'restock', 'waste') then raise exception 'Tipe perubahan stok tidak valid.'; end if;
  select * into v_ingredient from public.ingredients where id = p_ingredient_id for update;
  if v_ingredient.id is null then raise exception 'Bahan tidak ditemukan.'; end if;
  if v_ingredient.stock + p_quantity < 0 then raise exception 'Stok tidak boleh negatif.'; end if;
  update public.ingredients set stock = stock + p_quantity where id = p_ingredient_id returning * into v_ingredient;
  insert into public.stock_ledger (ingredient_id, change_type, quantity, notes)
  values (p_ingredient_id, 'adjustment', p_quantity, coalesce(p_change_type || ': ', '') || coalesce(p_notes, 'Penyesuaian stok owner'));
  return v_ingredient;
end;
$$;

revoke all on function public.create_order(text, jsonb) from public;
grant execute on function public.create_order(text, jsonb) to anon, authenticated;
revoke all on function public.confirm_cash_payment(uuid) from public, anon;
revoke all on function public.update_order_status(uuid, text) from public, anon;
revoke all on function public.adjust_stock(text, integer, text, text) from public, anon;
revoke all on function public.cancel_order(uuid, text) from public, anon;
grant execute on function public.confirm_cash_payment(uuid) to authenticated;
grant execute on function public.update_order_status(uuid, text) to authenticated;
grant execute on function public.adjust_stock(text, integer, text, text) to authenticated;
grant execute on function public.cancel_order(uuid, text) to authenticated;

-- Fungsi laporan mungkin belum ada pada schema awal; amankan bila tersedia.
do $$
begin
  if to_regprocedure('public.get_financial_report(date,date)') is not null then
    execute 'revoke all on function public.get_financial_report(date, date) from public, anon';
    execute 'grant execute on function public.get_financial_report(date, date) to authenticated';
  end if;
  if to_regprocedure('public.get_product_analytics(date,date)') is not null then
    execute 'revoke all on function public.get_product_analytics(date, date) from public, anon';
    execute 'grant execute on function public.get_product_analytics(date, date) to authenticated';
  end if;
end;
$$;
