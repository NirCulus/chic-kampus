<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { requireSupabase } from '../../supabase'

const reviews = ref([])
const summary = ref({ average_rating: 0, review_count: 0, satisfied_percent: 0 })
const filterRating = ref(0)
const loading = ref(false)
const errorMessage = ref('')
let reviewsChannel = null
const filteredReviews = computed(() => filterRating.value
  ? reviews.value.filter((review) => review.rating === filterRating.value)
  : reviews.value)
const distribution = computed(() => [5, 4, 3, 2, 1].map((rating) => ({
  rating,
  count: reviews.value.filter((review) => review.rating === rating).length,
})))
const ratingFilters = computed(() => [
  { rating: 0, label: 'Semua', count: reviews.value.length },
  ...distribution.value.map((row) => ({ rating: row.rating, label: `${row.rating} bintang`, count: row.count })),
])
const date = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))

async function loadReviews() {
  loading.value = true
  errorMessage.value = ''
  try {
    const client = requireSupabase()
    const [reviewResult, summaryResult] = await Promise.all([
      client.from('reviews')
        .select('id, order_id, customer_name, rating, comment, created_at, orders(queue_number, business_date)')
        .order('created_at', { ascending: false })
        .limit(200),
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
}

onMounted(async () => {
  await loadReviews()
  reviewsChannel = requireSupabase()
    .channel('owner-customer-reviews')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reviews' }, loadReviews)
    .subscribe()
})

onBeforeUnmount(() => {
  if (reviewsChannel) requireSupabase().removeChannel(reviewsChannel)
})
</script>

<template>
  <section>
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Suara pelanggan</p>
        <h2 class="mt-1 text-xl font-black">Ulasan pelanggan</h2>
        <p class="mt-1 text-sm text-stone-500">Ulasan terbaru diperbarui otomatis.</p>
      </div>
      <button class="rounded-xl border border-orange-200 bg-white px-4 py-2 text-sm font-bold text-chic-orange disabled:opacity-60" type="button" :disabled="loading" @click="loadReviews">{{ loading ? 'Memuat…' : 'Muat ulang' }}</button>
    </div>

    <p v-if="errorMessage" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ errorMessage }}</p>

    <div class="mt-5 grid gap-3 sm:grid-cols-3">
      <article class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <p class="text-xs font-bold uppercase text-stone-500">Rating rata-rata</p>
        <p class="mt-2 text-3xl font-black text-chic-orange">★ {{ Number(summary.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) }}<span class="text-sm text-stone-400"> / 5</span></p>
      </article>
      <article class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <p class="text-xs font-bold uppercase text-stone-500">Jumlah ulasan</p>
        <p class="mt-2 text-3xl font-black">{{ Number(summary.review_count).toLocaleString('id-ID') }}</p>
      </article>
      <article class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <p class="text-xs font-bold uppercase text-stone-500">Pelanggan puas (4–5★)</p>
        <p class="mt-2 text-3xl font-black text-emerald-700">{{ summary.satisfied_percent }}%</p>
      </article>
    </div>

    <div class="mt-5 grid gap-5 lg:grid-cols-[0.8fr_1.2fr]">
      <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <h3 class="font-black">Sebaran rating terbaru</h3>
        <div class="mt-4 space-y-3">
          <div v-for="row in distribution" :key="row.rating" class="flex items-center gap-3">
            <button class="w-10 text-left text-sm font-bold" type="button" @click="filterRating = filterRating === row.rating ? 0 : row.rating">{{ row.rating }} ★</button>
            <div class="h-2 flex-1 overflow-hidden rounded-full bg-stone-100"><div class="h-full rounded-full bg-chic-orange" :style="{ width: `${reviews.length ? row.count / reviews.length * 100 : 0}%` }"></div></div>
            <span class="w-8 text-right text-xs text-stone-500">{{ row.count }}</span>
          </div>
        </div>
        <p class="mt-4 text-xs text-stone-500">Distribusi berdasarkan 200 ulasan terbaru yang ditampilkan.</p>
      </section>

      <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div><h3 class="font-black">Ulasan terbaru</h3><p class="mt-1 text-xs text-stone-500">{{ filterRating ? `Filter ${filterRating} bintang` : 'Semua rating' }}</p></div>
          <div class="flex flex-wrap gap-1.5" aria-label="Filter ulasan berdasarkan rating">
            <button v-for="filter in ratingFilters" :key="filter.rating" class="rounded-full px-3 py-1.5 text-xs font-bold" :class="filterRating === filter.rating ? 'bg-chic-orange text-white' : 'bg-orange-50 text-chic-orange'" type="button" @click="filterRating = filter.rating">{{ filter.label }} ({{ filter.count }})</button>
          </div>
        </div>
        <div v-if="filteredReviews.length" class="mt-3 divide-y divide-stone-100">
          <article v-for="review in filteredReviews" :key="review.id" class="py-4">
            <div class="flex items-start gap-3">
              <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-orange-50 font-black text-chic-orange">{{ review.customer_name.slice(0, 1).toUpperCase() }}</span>
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center justify-between gap-2"><h4 class="font-bold">{{ review.customer_name }}</h4><span class="text-sm tracking-wide text-amber-500" :aria-label="`${review.rating} dari 5 bintang`">{{ '★'.repeat(review.rating) }}{{ '☆'.repeat(5 - review.rating) }}</span></div>
                <p class="mt-1 text-xs text-stone-500">{{ date(review.created_at) }} · Pesanan #{{ review.orders?.queue_number ?? '—' }}</p>
                <p class="mt-3 whitespace-pre-wrap text-sm text-stone-700">{{ review.comment || 'Tanpa komentar.' }}</p>
              </div>
            </div>
          </article>
        </div>
        <p v-else class="mt-5 rounded-xl bg-stone-50 p-6 text-center text-sm text-stone-500">{{ loading ? 'Memuat ulasan…' : 'Belum ada ulasan untuk filter ini.' }}</p>
      </section>
    </div>
  </section>
</template>
