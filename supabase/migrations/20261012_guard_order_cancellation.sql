create or replace function public.cancel_order(p_order_id uuid, p_notes text default 'Pesanan dibatalkan oleh owner.')
returns public.orders language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_item record;
  v_chicken_id text;
  v_sauce_id text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if v_order.status = 'cancelled' then raise exception 'Pesanan sudah dibatalkan.'; end if;
  if v_order.status = 'completed' then raise exception 'Pesanan yang sudah selesai tidak dapat dibatalkan.'; end if;

  for v_item in select * from public.order_items where order_id = p_order_id loop
    v_chicken_id := case v_item.size when 'small' then 'chicken_sm' when 'medium' then 'chicken_md' when 'large' then 'chicken_lg' end;
    v_sauce_id := case v_item.sauce_variant
      when 'classic_cheese' then 'sauce_classic'
      when 'hot_lava' then 'sauce_lava'
      when 'magic_mushroom' then 'sauce_mushroom'
      when 'black_thunder' then 'sauce_thunder'
    end;
    update public.ingredients set stock = stock + v_item.qty where id in (v_chicken_id, v_sauce_id, v_item.carb_type, 'packaging');
    insert into public.stock_ledger (ingredient_id, order_id, change_type, quantity, notes) values
      (v_chicken_id, p_order_id, 'refund', v_item.qty, p_notes),
      (v_sauce_id, p_order_id, 'refund', v_item.qty, p_notes),
      (v_item.carb_type, p_order_id, 'refund', v_item.qty, p_notes),
      ('packaging', p_order_id, 'refund', v_item.qty, p_notes);
  end loop;

  update public.orders
  set status = 'cancelled', payment_status = 'void'
  where id = p_order_id
  returning * into v_order;
  return v_order;
end;
$$;
