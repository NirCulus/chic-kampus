<script setup>
import { computed, onMounted, ref } from 'vue'
import { getCarb, getSauce, getSize } from '../../constants/menu'
import { requireSupabase } from '../../supabase'

const today = new Date()
const toDateInput = (date) => new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1)
const preset = ref('today')
const startDate = ref(toDateInput(today))
const endDate = ref(toDateInput(today))
const report = ref(null)
const analytics = ref([])
const loading = ref(false)
const errorMessage = ref('')
const rangeLabel = computed(() => `${new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium' }).format(new Date(`${startDate.value}T00:00:00`))} – ${new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium' }).format(new Date(`${endDate.value}T00:00:00`))}`)
const money = (value) => `Rp${Number(value ?? 0).toLocaleString('id-ID')}`

function applyPreset(value) {
  preset.value = value
  const end = new Date()
  const start = new Date()
  if (value === 'week') start.setDate(end.getDate() - 6)
  if (value === 'month') start.setDate(start.getDate() - (start.getDate() - 1))
  startDate.value = toDateInput(start)
  endDate.value = toDateInput(end)
}

function useCustomRange() { preset.value = 'custom' }
function menuLabel(item) {
  return `${getSize(item.size)?.label ?? item.size} · ${getSauce(item.sauce_variant)?.label ?? item.sauce_variant} · ${getCarb(item.carb_type)?.label ?? item.carb_type}`
}

async function loadReport() {
  if (!startDate.value || !endDate.value || startDate.value > endDate.value) { errorMessage.value = 'Rentang tanggal belum valid.'; return }
  loading.value = true; errorMessage.value = ''
  try {
    const client = requireSupabase()
    const [financialResult, productResult] = await Promise.all([
      client.rpc('get_financial_report', { p_start_date: startDate.value, p_end_date: endDate.value }),
      client.rpc('get_product_analytics', { p_start_date: startDate.value, p_end_date: endDate.value }),
    ])
    if (financialResult.error) throw financialResult.error
    if (productResult.error) throw productResult.error
    report.value = financialResult.data?.[0] ?? { revenue: 0, transaction_count: 0, average_transaction: 0, cash_revenue: 0, qris_revenue: 0 }
    analytics.value = productResult.data ?? []
  } catch (error) { errorMessage.value = error.message || 'Laporan belum dapat dimuat.' } finally { loading.value = false }
}

onMounted(loadReport)
</script>

<template>
  <section>
    <div class="flex flex-wrap items-end justify-between gap-3"><div><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Pembukuan</p><h2 class="mt-1 text-xl font-black">Ringkasan keuangan</h2><p class="mt-1 text-sm text-stone-500">Hanya pesanan yang sudah lunas dihitung dalam omzet.</p></div><span class="rounded-full bg-orange-50 px-3 py-2 text-xs font-bold text-chic-orange">{{ rangeLabel }}</span></div>
    <div class="mt-5 rounded-2xl border border-orange-100 bg-white p-4 shadow-sm"><div class="flex flex-wrap gap-2"><button v-for="option in [{ id: 'today', label: 'Hari ini' }, { id: 'week', label: '7 hari terakhir' }, { id: 'month', label: 'Bulan ini' }]" :key="option.id" class="rounded-xl px-3 py-2 text-sm font-bold" :class="preset === option.id ? 'bg-chic-orange text-white' : 'bg-orange-50 text-chic-orange'" type="button" @click="applyPreset(option.id)">{{ option.label }}</button></div><div class="mt-4 grid gap-3 sm:grid-cols-[1fr_1fr_auto]"><label class="text-sm font-bold">Dari<input v-model="startDate" class="mt-1 w-full rounded-xl border border-stone-200 px-3 py-2" type="date" @change="useCustomRange"></label><label class="text-sm font-bold">Sampai<input v-model="endDate" class="mt-1 w-full rounded-xl border border-stone-200 px-3 py-2" type="date" @change="useCustomRange"></label><button class="self-end rounded-xl bg-chic-orange px-4 py-2.5 text-sm font-bold text-white disabled:bg-stone-300" :disabled="loading" type="button" @click="loadReport">{{ loading ? 'Memuat…' : 'Terapkan' }}</button></div></div>
    <p v-if="errorMessage" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ errorMessage }}</p>
    <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article v-for="card in [{ label: 'Omzet', value: money(report?.revenue), tone: 'text-chic-orange' }, { label: 'Transaksi lunas', value: report?.transaction_count ?? 0, tone: 'text-chic-ink' }, { label: 'Rata-rata transaksi', value: money(report?.average_transaction), tone: 'text-chic-ink' }, { label: 'Laba/rugi', value: 'Belum tersedia', tone: 'text-stone-500' }]" :key="card.label" class="rounded-2xl border border-orange-100 bg-white p-4 shadow-sm"><p class="text-xs font-bold uppercase tracking-wide text-stone-500">{{ card.label }}</p><p class="mt-3 text-2xl font-black" :class="card.tone">{{ card.value }}</p><p v-if="card.label === 'Laba/rugi'" class="mt-2 text-xs text-stone-500">Butuh HPP dan biaya operasional.</p></article></div>
    <div class="mt-5 grid gap-5 lg:grid-cols-[0.8fr_1.2fr]"><section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm"><h3 class="font-black">Metode pembayaran</h3><div class="mt-5 space-y-4"><div><div class="flex justify-between text-sm font-bold"><span>QRIS</span><span>{{ money(report?.qris_revenue) }}</span></div><div class="mt-2 h-3 overflow-hidden rounded-full bg-stone-100"><div class="h-full rounded-full bg-chic-orange" :style="{ width: Number(report?.revenue) ? `${Math.round(Number(report?.qris_revenue) / Number(report?.revenue) * 100)}%` : '0%' }"></div></div></div><div><div class="flex justify-between text-sm font-bold"><span>Tunai</span><span>{{ money(report?.cash_revenue) }}</span></div><div class="mt-2 h-3 overflow-hidden rounded-full bg-stone-100"><div class="h-full rounded-full bg-amber-500" :style="{ width: Number(report?.revenue) ? `${Math.round(Number(report?.cash_revenue) / Number(report?.revenue) * 100)}%` : '0%' }"></div></div></div></div></section><section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm"><div class="flex items-center justify-between"><h3 class="font-black">Menu terlaris</h3><span class="text-xs text-stone-500">Berdasarkan penjualan lunas</span></div><div v-if="analytics.length" class="mt-4 divide-y divide-stone-100"><article v-for="(item, index) in analytics" :key="`${item.size}-${item.sauce_variant}-${item.carb_type}`" class="flex items-center gap-3 py-3"><span class="grid h-7 w-7 place-items-center rounded-full bg-orange-50 text-xs font-black text-chic-orange">{{ index + 1 }}</span><div class="min-w-0 flex-1"><p class="truncate text-sm font-bold">{{ menuLabel(item) }}</p><p class="mt-1 text-xs text-stone-500">{{ item.total_qty }} porsi</p></div><b class="text-sm">{{ money(item.total_sales) }}</b></article></div><p v-else class="mt-5 rounded-xl bg-stone-50 p-5 text-center text-sm text-stone-500">Belum ada transaksi lunas pada periode ini.</p></section></div>
  </section>
</template>