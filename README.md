# Chic Kampus

Prototype web self-service untuk pemesanan Chicken Steak Chic Kampus, dengan Kiosk pelanggan dan Dashboard Owner untuk antrean, stok, serta pembukuan omzet.

## Fitur

- Kiosk tablet: pilih ukuran, saus, karbohidrat, pembayaran QRIS/tunai, nomor antrean, dan unduhan PDF struk portrait berukuran khusus yang mengikuti teks dan isi pesanan.
- Owner: login email/password, antrean realtime, konfirmasi tunai, pembatalan pesanan tunai sebelum konfirmasi, status pesanan, stok bahan dan kemasan, HPP estimasi, ulasan, serta satu halaman keuangan dan penjualan.
- Ulasan pelanggan: formulir rating setelah pemesanan, halaman ulasan publik, ringkasan Owner, filter berdasarkan rating, dan daftar ulasan terbaru.
- Keuangan & penjualan: filter rentang tanggal, perbandingan KPI dengan periode sebelumnya, grafik harian yang dapat ditelusuri hingga per jam, rekap per jam/per transaksi, metode pembayaran dalam grafik batang atau donat, dan ekspor CSV/PDF multi-halaman.
- Supabase: PostgreSQL, Auth, RLS, RPC, dan Realtime.

## Menjalankan lokal

Prasyarat: Node.js 20+, Docker Desktop, dan Supabase CLI (terpasang sebagai dependency proyek).

```bash
npm install
npx supabase start
npm run dev
```

Aplikasi: `http://127.0.0.1:5173/kiosk`  
Login Owner: `http://127.0.0.1:5173/owner/login`  
Supabase Studio: `http://127.0.0.1:54323`

Buat akun Owner melalui Supabase Studio > Authentication > Users sebelum login.

## Environment

`.env.local` dipakai untuk koneksi Supabase aktif dan tidak boleh di-commit. Untuk lokal, gunakan URL dan anon/publishable key dari `npx supabase status`. Jangan pernah memakai service-role key di frontend.

## Database

Migrasi berada di `supabase/migrations/`. Untuk membangun ulang database lokal:

```bash
npx supabase db reset
```

## Build

```bash
npm run build
```

## Deploy ke Vercel

Import repository GitHub privat `NirCulus/chic-kampus` ke Vercel. Gunakan framework preset Vite, build command `npm run build`, dan output directory `dist`. Tambahkan environment variable Production berikut dari project Supabase Cloud:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Jangan gunakan URL localhost atau `service_role` key di frontend. `vercel.json` mengarahkan route aplikasi kembali ke `index.html` agar `/kiosk` dan `/owner/login` dapat dibuka langsung.

## HPP dan laporan

Migrasi `20261014_reviews_and_financial_reporting.sql` menambahkan biaya satuan bahan, snapshot HPP pada setiap item pesanan, tabel ulasan, dan RPC rekap. Jalankan migrasi sebelum memakai fitur keuangan/ulasan baru (`npx supabase db reset` untuk database lokal).
Migrasi `20261116_hourly_and_transaction_sales_recap.sql` menambahkan RPC khusus Owner untuk rincian penjualan per jam dan per transaksi.

Harga bahan awal adalah estimasi; owner dapat mengubah HPP satuan pada tab **Stok & HPP**. Tab **Keuangan & penjualan** menyatukan ringkasan, grafik, dan rekap dengan filter periode yang sama. Ekspor PDF disusun sebagai dokumen laporan berhalaman (teks, tabel, dan grafik), bukan tangkapan layar. Laporan memakai biaya bahan yang tersimpan saat pesanan dibuat agar perubahan biaya tidak mengubah riwayat. Laba yang ditampilkan adalah laba kotor estimasi (omzet dikurangi HPP bahan), belum dikurangi biaya operasional.

Saat satu tanggal dipilih, grafik menampilkan transaksi per jam; rekap dapat dialihkan antara ringkasan per jam dan per transaksi. Kartu KPI membandingkan rentang aktif dengan jumlah hari yang sama sebelumnya (rating dibandingkan dalam poin, bukan persen). Untuk memperbarui data demo cloud, `supabase/snippets/replace_cloud_demo_sales.sql` hanya mengganti baris dengan ID demo seed yang dikenal, mempertahankan data lain, dan membatalkan proses bila menemukan mutasi stok terkait.

## Catatan prototype

QRIS adalah simulasi browser. Struk dibuat sebagai PDF portrait khusus yang dapat dicetak dari PDF viewer. Owner hanya dapat membatalkan pesanan tunai yang belum dikonfirmasi; pembatalan memulihkan stok dan menandai pembayaran batal. HPP memakai harga bahan estimasi yang perlu disesuaikan dengan pembelian aktual; biaya operasional belum dicatat.