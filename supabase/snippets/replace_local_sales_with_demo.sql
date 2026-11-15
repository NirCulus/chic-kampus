-- Destructive local-only seed: replaces orders, reviews, and order-linked stock ledger rows.
-- Ingredient balances and unlinked manual stock adjustments are preserved.
do $seed$
declare
  v_today date := timezone('Asia/Jakarta', now())::date;
  v_business_date date;
  v_day_offset integer;
  v_orders_per_day integer;
  v_queue_number integer;
  v_order_id uuid;
  v_payment_method text;
  v_payment_status text;
  v_status text;
  v_cancelled boolean;
  v_waiting_cash boolean;
  v_created_at timestamptz;
  v_hour integer;
  v_item_count integer;
  v_item_index integer;
  v_size text;
  v_sauce text;
  v_carb text;
  v_qty integer;
  v_price integer;
  v_total numeric(12, 2);
  v_subtotal numeric(12, 2);
  v_rating integer;
  v_rating_roll numeric;
  v_name text;
  v_comment text;
  v_names text[] := array[
    'Alya', 'Bima', 'Citra', 'Daffa', 'Elsa', 'Farhan', 'Gita', 'Hana',
    'Intan', 'Jovan', 'Kirana', 'Luthfi', 'Maya', 'Nadia', 'Rafi', 'Salsa',
    'Tegar', 'Vina', 'Wulan', 'Yoga'
  ];
  v_five_star_comments text[] := array[
    'Sausnya enak dan porsinya pas!',
    'Pesanannya cepat, rasanya juga konsisten.',
    'Hot Lava jadi favorit. Pasti pesan lagi.',
    'Harga ramah mahasiswa dan mengenyangkan.',
    'Ayamnya juicy, kentangnya juga enak.'
  ];
  v_four_star_comments text[] := array[
    'Enak, mungkin sausnya bisa sedikit lebih banyak.',
    'Porsinya pas untuk makan siang.',
    'Rasanya cocok, pelayanan juga baik.',
    'Kentangnya enak. Semoga ada pilihan minuman.'
  ];
  v_three_star_comments text[] := array[
    'Cukup enak, tetapi tadi menunggu agak lama.',
    'Rasanya lumayan. Nasi bisa lebih hangat.',
    'Porsi sesuai harga, sausnya terasa biasa saja.'
  ];
  v_two_star_comments text[] := array[
    'Pesanan datang agak lama saat jam ramai.',
    'Ayamnya sedikit kering hari ini.'
  ];
  v_one_star_comments text[] := array[
    'Pesanan saya kurang sesuai. Semoga berikutnya lebih baik.',
    'Tadi menunggu cukup lama.'
  ];
begin
  delete from public.reviews;
  delete from public.stock_ledger where order_id is not null;
  delete from public.orders;

  for v_day_offset in reverse 365..0 loop
    v_business_date := v_today - v_day_offset;
    if extract(isodow from v_business_date) in (6, 7) then
      v_orders_per_day := 2 + floor(random() * 5)::integer;
    else
      v_orders_per_day := 6 + floor(random() * 9)::integer;
    end if;

    for v_queue_number in 1..v_orders_per_day loop
      v_payment_method := case when random() < 0.65 then 'qris' else 'cash' end;
      v_cancelled := random() < 0.025;
      v_waiting_cash := not v_cancelled
        and v_payment_method = 'cash'
        and v_business_date >= v_today - 2
        and random() < 0.18;
      v_payment_status := case
        when v_cancelled then 'void'
        when v_waiting_cash then 'waiting'
        else 'paid'
      end;
      v_status := case
        when v_cancelled then 'cancelled'
        when v_waiting_cash then 'waiting'
        when v_business_date < v_today - 2 then 'completed'
        when random() < 0.75 then 'completed'
        else 'processing'
      end;

      if random() < 0.58 then
        v_hour := 11 + floor(random() * 3)::integer;
      else
        v_hour := 9 + floor(random() * 12)::integer;
      end if;
      v_created_at := (
        v_business_date::timestamp
        + make_interval(hours => v_hour, mins => floor(random() * 60)::integer)
      ) at time zone 'Asia/Jakarta';

      insert into public.orders (
        queue_number, business_date, payment_method, payment_status, status, total_revenue, created_at
      ) values (
        v_queue_number, v_business_date, v_payment_method, v_payment_status, v_status, 0, v_created_at
      )
      returning id into v_order_id;

      v_total := 0;
      v_item_count := 1 + floor(random() * 3)::integer;
      for v_item_index in 1..v_item_count loop
        v_size := (array['small', 'medium', 'large'])[1 + floor(random() * 3)::integer];
        v_sauce := (array['classic_cheese', 'hot_lava', 'magic_mushroom', 'black_thunder'])[1 + floor(random() * 4)::integer];
        v_carb := (array['rice', 'fries'])[1 + floor(random() * 2)::integer];
        v_qty := 1 + floor(random() * 2)::integer;
        v_price := case v_size
          when 'small' then 15000
          when 'medium' then 17000
          else 22000
        end;
        v_subtotal := v_price * v_qty;
        v_total := v_total + v_subtotal;

        insert into public.order_items (order_id, size, sauce_variant, carb_type, qty, subtotal)
        values (v_order_id, v_size, v_sauce, v_carb, v_qty, v_subtotal);
      end loop;

      update public.orders set total_revenue = v_total where id = v_order_id;

      if v_payment_status = 'paid'
        and v_status = 'completed'
        and random() < 0.22
      then
        v_rating_roll := random();
        v_rating := case
          when v_rating_roll < 0.48 then 5
          when v_rating_roll < 0.75 then 4
          when v_rating_roll < 0.88 then 3
          when v_rating_roll < 0.96 then 2
          else 1
        end;
        v_name := v_names[1 + floor(random() * array_length(v_names, 1))::integer];
        v_comment := case v_rating
          when 5 then v_five_star_comments[1 + floor(random() * array_length(v_five_star_comments, 1))::integer]
          when 4 then v_four_star_comments[1 + floor(random() * array_length(v_four_star_comments, 1))::integer]
          when 3 then v_three_star_comments[1 + floor(random() * array_length(v_three_star_comments, 1))::integer]
          when 2 then v_two_star_comments[1 + floor(random() * array_length(v_two_star_comments, 1))::integer]
          else v_one_star_comments[1 + floor(random() * array_length(v_one_star_comments, 1))::integer]
        end;

        insert into public.reviews (order_id, customer_name, rating, comment, created_at)
        values (
          v_order_id,
          v_name,
          v_rating,
          v_comment,
          v_created_at + make_interval(mins => 10 + floor(random() * 180)::integer)
        );
      end if;
    end loop;
  end loop;
end;
$seed$;
