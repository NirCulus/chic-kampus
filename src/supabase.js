import { createClient } from '@supabase/supabase-js'

// Mengambil variabel lingkungan dari file .env.local
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

// Client hanya dibuat jika variabel lingkungan sudah terisi agar halaman Kiosk
// tetap dapat dirender dan memberi pesan yang jelas saat setup belum selesai.
export const supabase = isSupabaseConfigured ? createClient(supabaseUrl, supabaseAnonKey) : null

export function requireSupabase() {
  if (!supabase) throw new Error('Supabase belum dikonfigurasi. Isi VITE_SUPABASE_URL dan VITE_SUPABASE_ANON_KEY di .env.local.')
  return supabase
}
