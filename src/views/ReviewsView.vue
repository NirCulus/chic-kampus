<script setup>
import { onMounted, ref } from 'vue'
import { requireSupabase } from '../supabase'

const reviews = ref([])
const summary = ref({ average_rating: 0, review_count: 0, satisfied_percent: 0 })
const loading = ref(true)
const errorMessage = ref('')
const date = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium' }).format(new Date(value))

onMounted(async () => {
  try {
    const client = requireSupabase()
    const [reviewResult, summaryResult] = await Promise.all([
      client.rpc('get_public_reviews', { p_limit: 50 }),
      client.rpc('get_review_summary'),
    ])
    if (reviewResult.error) throw reviewResult.error
    if (summaryResult.error) throw summaryResult.error
    reviews.value = reviewResult.data ?? []
    summary.value = summaryResult.data?.[0] ?? summary.value
  } catch (error) {
    errorMessage.value = error.message || 'Ulasan belum dapat dimuat.'
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="min-h-screen bg-chic-cream px-5 py-8 text-chic-ink">
    <div class="mx-auto max-w-4xl">
      <RouterLink class="inline-flex items-center gap-2 text-sm font-bold text-chic-orange" to="/kiosk">← Kembali ke menu</RouterLink>
      <header class="mt-6 rounded-3xl bg-chic-ink p-7 text-white sm:p-10">
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-orange-200">Cerita pelanggan</p>
        <h1 class="mt-2 text-3xl font-black">Ulasan Chic Kampus</h1>
        <p class="mt-2 text-sm text-stone-300">Ulasan diberikan oleh pelanggan setelah pesanan berhasil dibuat.</p>
        <div class="mt-6 flex flex-wrap gap-8">
          <div><p class="text-xs text-stone-300">Rating rata-rata</p><p class="mt-1 text-2xl font-black text-orange-200">★ {{ Number(summary.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) }} / 5</p></div>
          <div><p class="text-xs text-stone-300">Jumlah ulasan</p><p class="mt-1 text-2xl font-black">{{ Number(summary.review_count).toLocaleString('id-ID') }}</p></div>
          <div><p class="text-xs text-stone-300">Pelanggan puas</p><p class="mt-1 text-2xl font-black">{{ summary.satisfied_percent }}%</p></div>
        </div>
      </header>

      <p v-if="errorMessage" class="mt-5 rounded-xl bg-red-50 p-4 text-sm text-red-700">{{ errorMessage }}</p>
      <section class="mt-5 rounded-3xl border border-orange-100 bg-white p-5 shadow-sm sm:p-7">
        <h2 class="text-xl font-black">Ulasan terbaru</h2>
        <div v-if="reviews.length" class="mt-3 divide-y divide-stone-100">
          <article v-for="(review, index) in reviews" :key="`${review.created_at}-${index}`" class="py-5">
            <div class="flex items-start gap-3">
              <span class="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-orange-50 font-black text-chic-orange">{{ review.customer_name.slice(0, 1).toUpperCase() }}</span>
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center justify-between gap-2"><h3 class="font-bold">{{ review.customer_name }}</h3><span class="text-sm tracking-wide text-amber-500" :aria-label="`${review.rating} dari 5 bintang`">{{ '★'.repeat(review.rating) }}{{ '☆'.repeat(5 - review.rating) }}</span></div>
                <p class="mt-1 text-xs text-stone-500">{{ date(review.created_at) }}</p>
                <p class="mt-3 whitespace-pre-wrap text-sm leading-6 text-stone-700">{{ review.comment || 'Pelanggan tidak menambahkan komentar.' }}</p>
              </div>
            </div>
          </article>
        </div>
        <p v-else class="mt-5 rounded-xl bg-stone-50 p-6 text-center text-sm text-stone-500">{{ loading ? 'Memuat ulasan…' : 'Belum ada ulasan. Silakan kembali setelah transaksi pelanggan pertama.' }}</p>
      </section>
      <p class="mt-4 text-center text-xs text-stone-500">Punya pesanan? Berikan rating pada layar konfirmasi setelah membuat pesanan.</p>
    </div>
  </main>
</template>
