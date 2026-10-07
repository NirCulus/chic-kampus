# Chic Kampus

Prototype web self-service untuk pemesanan Chicken Steak Chic Kampus, dengan Kiosk pelanggan dan Dashboard Owner untuk antrean, stok, serta pembukuan omzet.

## Fitur

- Kiosk tablet: pilih ukuran, saus, karbohidrat, pembayaran QRIS/tunai, nomor antrean, dan struk thermal browser.
- Owner: login email/password, antrean realtime, konfirmasi tunai, status pesanan, struk, stok bahan dan kemasan, ledger, serta laporan omzet.
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

## Catatan prototype

QRIS dan cetak struk adalah simulasi browser. Laporan keuangan menampilkan omzet; laba/rugi belum tersedia karena HPP dan biaya operasional belum dicatat.