-- Replaces only the prior deterministic Chic Kampus demo orders/reviews.
-- Preserves real cloud orders and refuses to proceed if demo orders affected stock.
-- The current business date is intentionally left to real orders to avoid future timestamps.
-- No ingredient balances or stock_ledger rows are changed.
do $seed$
declare
  v_start_date date := date '2025-11-15';
  v_end_date date := date '2026-11-16';
  v_cost_count integer;
  v_old_seed_count integer;
  v_ledger_count integer;
  v_preserved_count bigint;
  v_inserted_count integer;
  v_review_count integer;
begin
  select count(*)
  into v_cost_count
  from public.ingredient_costs
  where ingredient_id in (
    'chicken_sm', 'chicken_md', 'chicken_lg',
    'sauce_classic', 'sauce_lava', 'sauce_mushroom', 'sauce_thunder',
    'rice', 'fries', 'packaging'
  );
  if v_cost_count <> 10 then
    raise exception 'Seed dibatalkan: HPP belum lengkap (ditemukan % dari 10 bahan).', v_cost_count;
  end if;

  perform pg_advisory_xact_lock(hashtext('chic-kampus-cloud-demo-seed-v2'));

  create temporary table chic_demo_seed_ids on commit drop as
  with days as (
    select generated_day::date as business_date
    from generate_series(v_start_date, v_end_date, interval '1 day') as dates(generated_day)
  ),
  slots as (
    select days.business_date, generated_slot.slot
    from days
    cross join generate_series(1, 60) as generated_slot(slot)
  )
  select
    md5('chic-kampus-cloud-demo-order:' || business_date::text || ':' || slot)::uuid as id
  from slots
  where slot <= 30
  union
  select
    md5('chic-kampus-cloud-demo-order-v2:' || business_date::text || ':' || slot)::uuid as id
  from slots;

  select count(*)
  into v_old_seed_count
  from public.orders as orders
  join chic_demo_seed_ids as seed_ids using (id);

  select count(*)
  into v_ledger_count
  from public.stock_ledger as ledger
  join chic_demo_seed_ids as seed_ids on seed_ids.id = ledger.order_id;
  if v_ledger_count > 0 then
    raise exception 'Seed dibatalkan: % mutasi stok terkait data demo. Stok tidak diubah.', v_ledger_count;
  end if;

  delete from public.orders as orders
  using chic_demo_seed_ids as seed_ids
  where orders.id = seed_ids.id;

  select count(*) into v_preserved_count from public.orders;

  create temporary table chic_demo_seed_orders on commit drop as
  with days as (
    select
      generated_day::date as business_date,
      (generated_day::date - v_start_date) as day_offset
    from generate_series(v_start_date, v_end_date, interval '1 day') as dates(generated_day)
  ),
  daily_volume as (
    select
      days.business_date,
      days.day_offset,
      case
        when days.business_date = timezone('Asia/Jakarta', now())::date then 0
        when extract(isodow from days.business_date) in (6, 7) then
          4 + abs(hashtextextended(days.business_date::text || ':weekend', 212) % 20)
          + case when extract(day from days.business_date) in (1, 15, 25) then 5 else 0 end
        else
          16 + abs(hashtextextended(days.business_date::text || ':weekday', 212) % 32)
          + case when extract(day from days.business_date) in (1, 15, 25) then 6 else 0 end
      end::integer as order_count
    from days
  ),
  daily_queue as (
    select
      daily_volume.business_date,
      daily_volume.day_offset,
      daily_volume.order_count,
      coalesce(max(orders.queue_number), 0) as last_queue_number
    from daily_volume
    left join public.orders as orders using (business_date)
    group by daily_volume.business_date, daily_volume.day_offset, daily_volume.order_count
  ),
  slots as (
    select
      daily_queue.business_date,
      daily_queue.day_offset,
      daily_queue.last_queue_number,
      generated_slot.slot
    from daily_queue
    cross join lateral generate_series(1, daily_queue.order_count) as generated_slot(slot)
  ),
  scheduled as (
    select
      slots.*,
      abs(hashtextextended(slots.business_date::text || ':' || slots.slot || ':hour', 428) % 100) as hour_roll,
      abs(hashtextextended(slots.business_date::text || ':' || slots.slot || ':minute', 428) % 60) as minute_roll,
      abs(hashtextextended(slots.business_date::text || ':' || slots.slot || ':basket', 428) % 3) + 1 as item_count,
      abs(hashtextextended(slots.business_date::text || ':' || slots.slot || ':pay', 428) % 100) as payment_roll
    from slots
  )
  select
    md5('chic-kampus-cloud-demo-order-v2:' || scheduled.business_date::text || ':' || scheduled.slot)::uuid as id,
    scheduled.business_date,
    scheduled.last_queue_number + scheduled.slot as queue_number,
    case when scheduled.payment_roll < 68 then 'qris' else 'cash' end as payment_method,
    'paid'::text as payment_status,
    'completed'::text as status,
    scheduled.item_count,
    scheduled.day_offset,
    scheduled.slot,
    (
      scheduled.business_date::timestamp
      + make_interval(
        hours => case
          when scheduled.hour_roll < 53 then 11 + abs(hashtextextended(scheduled.business_date::text || ':' || scheduled.slot || ':lunch', 816) % 3)
          when scheduled.hour_roll < 86 then 17 + abs(hashtextextended(scheduled.business_date::text || ':' || scheduled.slot || ':dinner', 816) % 4)
          else 9 + abs(hashtextextended(scheduled.business_date::text || ':' || scheduled.slot || ':offpeak', 816) % 12)
        end::integer,
        mins => scheduled.minute_roll::integer
      )
    ) at time zone 'Asia/Jakarta' as created_at,
    0::numeric(12, 2) as total_revenue
  from scheduled;

  create temporary table chic_demo_seed_items on commit drop as
  select
    md5(
      'chic-kampus-cloud-demo-item-v2:' || seed.business_date::text || ':' ||
      seed.slot || ':' || generated_item.item_number
    )::uuid as id,
    seed.id as order_id,
    (array['small', 'medium', 'large'])
      [1 + abs(hashtextextended(seed.id::text || ':' || generated_item.item_number || ':size', 931) % 3)] as size,
    (array['classic_cheese', 'hot_lava', 'magic_mushroom', 'black_thunder'])
      [1 + abs(hashtextextended(seed.id::text || ':' || generated_item.item_number || ':sauce', 931) % 4)] as sauce_variant,
    case
      when abs(hashtextextended(seed.id::text || ':' || generated_item.item_number || ':carb', 931) % 2) = 0 then 'rice'
      else 'fries'
    end as carb_type,
    1 + abs(hashtextextended(seed.id::text || ':' || generated_item.item_number || ':qty', 931) % 2) as qty
  from chic_demo_seed_orders as seed
  cross join lateral generate_series(1, seed.item_count) as generated_item(item_number);

  update chic_demo_seed_orders as seed
  set total_revenue = item_totals.total_revenue
  from (
    select
      items.order_id,
      sum((case items.size when 'small' then 15000 when 'medium' then 17000 else 22000 end) * items.qty)::numeric(12, 2) as total_revenue
    from chic_demo_seed_items as items
    group by items.order_id
  ) as item_totals
  where item_totals.order_id = seed.id;

  insert into public.orders (
    id, business_date, queue_number, payment_method, payment_status, status,
    total_revenue, created_at, updated_at
  )
  select
    id, business_date, queue_number, payment_method, payment_status, status,
    total_revenue, created_at, created_at
  from chic_demo_seed_orders;

  insert into public.order_items (id, order_id, size, sauce_variant, carb_type, qty, subtotal)
  select
    items.id,
    items.order_id,
    items.size,
    items.sauce_variant,
    items.carb_type,
    items.qty,
    (case items.size when 'small' then 15000 when 'medium' then 17000 else 22000 end) * items.qty
  from chic_demo_seed_items as items;

  create temporary table chic_demo_seed_reviews on commit drop as
  with review_orders as (
    select
      seed.*,
      case
        when seed.payment_roll < 58 then 5
        when seed.payment_roll < 83 then 4
        when seed.payment_roll < 93 then 3
        when seed.payment_roll < 98 then 2
        else 1
      end as rating
    from (
      select
        orders.*,
        abs(hashtextextended(orders.id::text || ':review', 304) % 100) as payment_roll
      from chic_demo_seed_orders as orders
    ) as seed
    where abs(hashtextextended(seed.id::text || ':review-eligibility', 304) % 100) < 23
  )
  select
    md5('chic-kampus-cloud-demo-review-v2:' || orders.id::text)::uuid as id,
    orders.id as order_id,
    (
      (array[
        'Alya', 'Bima', 'Citra', 'Daffa', 'Elsa', 'Farhan', 'Gita', 'Hana',
        'Intan', 'Jovan', 'Kirana', 'Luthfi', 'Maya', 'Nadia', 'Rafi', 'Salsa',
        'Tegar', 'Vina', 'Wulan', 'Yoga', 'Aditya', 'Bella', 'Dimas', 'Nabila',
        'Rizky', 'Tiara', 'Fajar', 'Nanda', 'Putri', 'Rangga'
      ])[1 + abs(hashtextextended(orders.id::text || ':first-name', 503) % 30)]
      || ' ' ||
      (array[
        'Adi', 'Ayu', 'Bagas', 'Cahya', 'Dewi', 'Eka', 'Fauzan', 'Indra',
        'Kartika', 'Mahesa', 'Ningrum', 'Pratama', 'Putra', 'Rahma', 'Sari',
        'Wicaksono', 'Wijaya', 'Kusuma', 'Permata', 'Utami'
      ])[1 + abs(hashtextextended(orders.id::text || ':middle-name', 503) % 20)]
      || ' ' ||
      (array[
        'Pradana', 'Saputra', 'Ramadhan', 'Permadi', 'Puspita', 'Ananda',
        'Kurniawan', 'Salsabila', 'Maulana', 'Wulandari', 'Nugroho', 'Lestari',
        'Setiawan', 'Anggraini', 'Firmansyah', 'Prameswari', 'Hidayat', 'Utomo',
        'Maharani', 'Santoso', 'Wirawan', 'Azzahra', 'Prakoso', 'Nirmala',
        'Pamungkas', 'Kusnadi', 'Fitria', 'Adinata', 'Pertiwi', 'Mahardika'
      ])[1 + abs(hashtextextended(orders.id::text || ':last-name', 503) % 30)]
    ) as customer_name,
    orders.rating,
    (
      (array[
        'Pesanan saya', 'Menu yang saya pilih', 'Paket makan siang ini',
        'Steak ayam dan pelengkapnya', 'Makan siang tadi', 'Porsi menunya',
        'Rasa dari pesanan saya', 'Pengalaman pesan lewat kiosk',
        'Menu medium yang saya coba', 'Pesanan untuk dibawa ke kelas',
        'Paket ayam dan nasi', 'Varian saus yang saya pilih', 'Menu untuk makan sore',
        'Pesanan bersama teman', 'Makan siang di kampus'
      ])[1 + abs(hashtextextended(orders.id::text || ':review-subject', 617) % 15)]
      || ' ' ||
      case orders.rating
        when 5 then (array[
          'terasa enak, ayamnya matang pas dan tetap juicy',
          'punya rasa gurih yang seimbang dan bikin kenyang',
          'datang hangat dengan porsi yang memuaskan',
          'cocok di lidah dan harganya terasa pas',
          'bumbunya meresap dan pelengkapnya juga enak',
          'rasanya konsisten dan proses pesanannya cepat',
          'jadi pilihan yang pas untuk makan sebelum kelas',
          'teksturnya pas dan sausnya terasa cocok',
          'rasanya mantap tanpa terasa terlalu berat',
          'memuaskan, terutama untuk makan siang di kampus',
          'disajikan dengan rapi dan masih hangat',
          'punya porsi yang pas untuk mengisi tenaga'
        ])[1 + abs(hashtextextended(orders.id::text || ':review-body', 619) % 12)]
        when 4 then (array[
          'enak dan mengenyangkan, hanya sausnya bisa sedikit lebih banyak',
          'rasanya cocok, meski kentangnya agak kurang renyah',
          'datang cukup hangat dan porsinya sesuai harga',
          'ayamnya enak, tetapi saya ingin pilihan saus lebih banyak',
          'prosesnya lancar, hanya perlu menunggu sebentar saat ramai',
          'gurihnya pas, walau tingkat pedasnya sedikit berbeda dari perkiraan',
          'cukup memuaskan untuk makan siang di sela jadwal',
          'rasanya enak, semoga konsistensi porsinya dipertahankan',
          'pelengkapnya cocok, tetapi nasinya bisa lebih hangat',
          'harganya pas dan menu ini akan saya pesan lagi',
          'ayamnya terasa juicy, hanya kemasannya agak sulit dibuka',
          'pesanannya sesuai, meski penyajiannya tadi sedikit lebih lama'
        ])[1 + abs(hashtextextended(orders.id::text || ':review-body', 619) % 12)]
        when 3 then (array[
          'rasanya cukup enak, tetapi belum terlalu berkesan',
          'porsinya sesuai harga, hanya bumbunya terasa biasa saja',
          'ayamnya lumayan, meski sausnya kurang merata',
          'cukup mengenyangkan dan masih ada beberapa hal yang bisa ditingkatkan',
          'pesanan sesuai, tetapi waktu tunggunya agak lama',
          'rasanya standar untuk makan siang cepat',
          'kentangnya enak, namun ayamnya sedikit kering',
          'tidak buruk, hanya rasa sausnya kurang cocok untuk saya',
          'porsinya pas, tetapi makanan tadi kurang hangat',
          'proses pesan mudah, pengalaman makannya biasa saja',
          'rasanya lumayan dan bisa dicoba lagi dengan varian lain',
          'menu ini cukup oke, meski belum menjadi favorit'
        ])[1 + abs(hashtextextended(orders.id::text || ':review-body', 619) % 12)]
        when 2 then (array[
          'ayamnya terasa agak kering dan sausnya kurang banyak',
          'pesanan datang lebih lama dari perkiraan saya',
          'makanannya kurang hangat saat saya terima',
          'rasa bumbunya kurang sesuai dengan yang saya harapkan',
          'kentangnya kurang renyah dan porsinya terasa sedikit',
          'saya perlu menunggu cukup lama saat jam makan siang',
          'menu yang diterima kurang rapi untuk dibawa',
          'sausnya terlalu sedikit sehingga rasanya kurang seimbang',
          'pesanan tidak terlalu cocok dengan selera saya',
          'ayamnya agak keras dan sulit dinikmati',
          'waktu penyajiannya perlu diperhatikan saat kondisi ramai',
          'rasanya kurang konsisten dibanding kunjungan sebelumnya'
        ])[1 + abs(hashtextextended(orders.id::text || ':review-body', 619) % 12)]
        else (array[
          'pesanan saya kurang sesuai dan makanannya sudah tidak hangat',
          'waktu tunggunya terlalu lama tanpa informasi yang jelas',
          'ayamnya terlalu kering sehingga sulit dinikmati',
          'rasa menu ini tidak sesuai dengan yang saya pesan',
          'sausnya hampir tidak terasa dan porsinya kurang memuaskan',
          'pengalaman kali ini mengecewakan bagi saya',
          'pesanan yang diterima kurang rapi dan sulit dibawa',
          'makanan tadi terasa kurang segar saat sampai',
          'saya berharap kualitas penyajiannya bisa diperbaiki',
          'pesanannya tidak sesuai harapan dan perlu lebih teliti',
          'rasa dan suhu makanannya kurang nyaman dinikmati',
          'pelayanan saat jam ramai perlu banyak ditingkatkan'
        ])[1 + abs(hashtextextended(orders.id::text || ':review-body', 619) % 12)]
      end
      || '. ' ||
      (array[
        'Saya datang saat jeda kuliah siang.',
        'Kiosk-nya mudah digunakan untuk memesan.',
        'Semoga masukan ini membantu perbaikan berikutnya.',
        'Saya mencoba menu ini bersama teman kampus.',
        'Pengalaman ini terjadi pada kunjungan sore.',
        'Saya memesan untuk dibawa setelah kelas.',
        'Catatan ini berdasarkan pesanan hari itu.',
        'Semoga kualitasnya makin konsisten ke depannya.',
        'Saya akan mempertimbangkan untuk mencoba lagi.',
        'Pesanan ini saya nikmati di area kampus.',
        'Saya mampir setelah menyelesaikan tugas.',
        'Pemesanan dilakukan pada jam istirahat.',
        'Saya memilih menu ini karena rekomendasi teman.',
        'Kunjungan kali ini cukup ramai.',
        'Saya makan bersama teman sekelas.',
        'Semoga pilihan menunya terus bertambah.',
        'Saya mencoba kombinasi saus yang berbeda.',
        'Pesanan ini dibuat sebelum jadwal kuliah.',
        'Saya mencatat pengalaman dari kunjungan hari ini.',
        'Mudah-mudahan catatan ini berguna untuk tim.',
        'Saya akan mencoba pilihan lain pada kunjungan berikutnya.'
      ])[1 + abs(hashtextextended(orders.id::text || ':review-context', 631) % 20)]
    ) as comment,
    orders.created_at + make_interval(
      mins => (12 + abs(hashtextextended(orders.id::text || ':review-minute', 701) % 180))::integer
    ) as created_at
  from review_orders as orders;

  insert into public.reviews (id, order_id, customer_name, rating, comment, created_at)
  select id, order_id, customer_name, rating, comment, created_at
  from chic_demo_seed_reviews;

  select count(*) into v_inserted_count from chic_demo_seed_orders;
  select count(*) into v_review_count from chic_demo_seed_reviews;

  if (select count(*) from public.orders) <> v_preserved_count + v_inserted_count then
    raise exception 'Seed dibatalkan: jumlah transaksi setelah seed tidak sesuai.';
  end if;

  if (select count(distinct business_date) from chic_demo_seed_orders) < 300
    or (select count(distinct daily_count) from (
      select business_date, count(*) as daily_count
      from chic_demo_seed_orders
      group by business_date
    ) as daily_volumes) < 20 then
    raise exception 'Seed dibatalkan: variasi transaksi harian tidak mencukupi.';
  end if;

  if v_review_count > 0
    and (select count(distinct comment) from chic_demo_seed_reviews) < v_review_count * 0.75 then
    raise exception 'Seed dibatalkan: variasi teks ulasan tidak mencukupi.';
  end if;

  raise notice 'Seed selesai: % data demo lama diganti dengan % pesanan dan % ulasan baru; % baris cloud non-demo dipertahankan.',
    v_old_seed_count, v_inserted_count, v_review_count, v_preserved_count;
end;
$seed$;
