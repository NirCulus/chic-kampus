<script setup>
import { computed, onMounted, ref } from 'vue'
import { getCarb, getSauce, getSize } from '../../constants/menu'
import { requireSupabase } from '../../supabase'
import { downloadFinancialReportPdf } from '../../utils/financialReportPdf'

const todayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Jakarta',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})
const dateFormatter = new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeZone: 'UTC' })
const money = (value) => `Rp${Math.round(Number(value ?? 0)).toLocaleString('id-ID')}`
const number = (value) => Number(value ?? 0).toLocaleString('id-ID')
const toDate = (value) => new Date(`${value}T00:00:00Z`)
const fromDate = (value) => value.toISOString().slice(0, 10)
const addDays = (value, days) => {
  const date = toDate(value)
  date.setUTCDate(date.getUTCDate() + days)
  return fromDate(date)
}
const addMonths = (value, months) => {
  const date = toDate(value)
  date.setUTCDate(1)
  date.setUTCMonth(date.getUTCMonth() + months)
  return fromDate(date)
}
const shiftMonths = (value, months) => {
  const date = toDate(value)
  const day = date.getUTCDate()
  date.setUTCDate(1)
  date.setUTCMonth(date.getUTCMonth() + months)
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate()
  date.setUTCDate(Math.min(day, lastDay))
  return fromDate(date)
}
const startOfMonth = (value) => `${value.slice(0, 7)}-01`
const lastDayOfMonth = (value) => addDays(addMonths(startOfMonth(value), 1), -1)
const today = () => {
  const parts = Object.fromEntries(todayFormatter.formatToParts(new Date()).map((part) => [part.type, part.value]))
  return `${parts.year}-${parts.month}-${parts.day}`
}
const daysBetween = (start, end) => Math.round((toDate(end) - toDate(start)) / 86400000) + 1
const formatDate = (value) => dateFormatter.format(toDate(value))

const datePresets = [
  { id: 'today', label: 'Hari ini' },
  { id: 'yesterday', label: 'Kemarin' },
  { id: 'last_7_days', label: '7 hari' },
  { id: 'last_30_days', label: '30 hari' },
  { id: 'month_to_date', label: 'Bulan ini' },
  { id: 'previous_month', label: 'Bulan lalu' },
  { id: 'last_90_days', label: '90 hari' },
  { id: 'year_to_date', label: 'Tahun berjalan' },
  { id: 'last_12_months', label: '12 bulan' },
]
const dateRange = ref({ start: startOfMonth(today()), end: today() })
const activePreset = ref('month_to_date')
const groupBy = ref('auto')
const advancedFiltersOpen = ref(false)
const financial = ref(null)
const products = ref([])
const trend = ref([])
const loading = ref(false)
const exporting = ref(false)
const errorMessage = ref('')
const validationMessage = ref('')
const hoveredPoint = ref(null)
const selectedPoint = ref(null)
let latestRequest = 0

const effectiveGroup = computed(() => {
  if (groupBy.value !== 'auto') return groupBy.value
  const days = daysBetween(dateRange.value.start, dateRange.value.end)
  return days <= 31 ? 'day' : days <= 180 ? 'week' : 'month'
})
const groupLabels = { day: 'hari', week: 'minggu', month: 'bulan' }
const dateRangeLabel = computed(() => `${formatDate(dateRange.value.start)} – ${formatDate(dateRange.value.end)}`)
const summary = computed(() => {
  const revenue = Number(financial.value?.revenue ?? 0)
  const estimatedCogs = trend.value.reduce((sum, row) => sum + Number(row.estimated_cogs), 0)
  const reviewCount = trend.value.reduce((sum, row) => sum + Number(row.review_count), 0)
  const ratingTotal = trend.value.reduce((sum, row) => sum + Number(row.average_rating) * Number(row.review_count), 0)
  const transactionCount = Number(financial.value?.transaction_count ?? 0)
  const grossProfit = revenue - estimatedCogs
  return {
    revenue,
    estimatedCogs,
    grossProfit,
    margin: revenue ? grossProfit / revenue * 100 : 0,
    transactionCount,
    portionCount: trend.value.reduce((sum, row) => sum + Number(row.portion_count), 0),
    averageTicket: transactionCount ? revenue / transactionCount : 0,
    cashRevenue: Number(financial.value?.cash_revenue ?? 0),
    qrisRevenue: Number(financial.value?.qris_revenue ?? 0),
    reviewCount,
    averageRating: reviewCount ? ratingTotal / reviewCount : 0,
  }
})
const chartRows = computed(() => [...trend.value].reverse())
const chartMax = computed(() => Math.max(1, ...chartRows.value.map((row) => Number(row.revenue))))
const selectedDetails = computed(() => hoveredPoint.value || selectedPoint.value)
const topProducts = computed(() => products.value.slice(0, 10).map((item) => ({
  ...item,
  label: `${getSize(item.size)?.label ?? item.size} · ${getSauce(item.sauce_variant)?.label ?? item.sauce_variant} · ${getCarb(item.carb_type)?.label ?? item.carb_type}`,
})))

function periodLabel(value) {
  const start = toDate(value)
  if (effectiveGroup.value === 'month') {
    return new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(start)
  }
  if (effectiveGroup.value === 'week') {
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 6)
    return `${formatDate(value)} – ${dateFormatter.format(end)}`
  }
  return formatDate(value)
}

function chartAxisLabel(row, index) {
  const stride = Math.max(1, Math.ceil(chartRows.value.length / 12))
  if (index % stride !== 0 && index !== chartRows.value.length - 1) return ''
  if (effectiveGroup.value === 'month') {
    return new Intl.DateTimeFormat('id-ID', { month: 'short', year: '2-digit', timeZone: 'UTC' }).format(toDate(row.period_start))
  }
  if (effectiveGroup.value === 'week') {
    return new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(toDate(row.period_start))
  }
  return row.period_start.slice(8)
}

function choosePreset(preset) {
  activePreset.value = preset
  if (preset === 'custom') {
    validationMessage.value = ''
    return
  }

  const end = today()
  let start = end
  if (preset === 'yesterday') {
    start = addDays(end, -1)
    dateRange.value.end = start
  } else if (preset === 'last_7_days') {
    start = addDays(end, -6)
  } else if (preset === 'last_30_days') {
    start = addDays(end, -29)
  } else if (preset === 'month_to_date') {
    start = startOfMonth(end)
  } else if (preset === 'previous_month') {
    const previousMonth = addMonths(startOfMonth(end), -1)
    start = previousMonth
    dateRange.value.end = lastDayOfMonth(previousMonth)
  } else if (preset === 'last_90_days') {
    start = addDays(end, -89)
  } else if (preset === 'year_to_date') {
    start = `${end.slice(0, 4)}-01-01`
  } else if (preset === 'last_12_months') {
    start = shiftMonths(end, -12)
  }
  if (preset !== 'yesterday' && preset !== 'previous_month') dateRange.value.end = end
  dateRange.value.start = start
  loadReport()
}

function chooseGroup(group) {
  groupBy.value = group
  loadReport()
}

async function loadReport() {
  validationMessage.value = ''
  if (!dateRange.value.start || !dateRange.value.end || dateRange.value.start > dateRange.value.end) {
    validationMessage.value = 'Tanggal mulai harus sama dengan atau sebelum tanggal akhir.'
    return
  }

  const requestId = ++latestRequest
  loading.value = true
  errorMessage.value = ''
  selectedPoint.value = null
  hoveredPoint.value = null
  try {
    const client = requireSupabase()
    const start = dateRange.value.start
    const end = dateRange.value.end
    const group = effectiveGroup.value
    const [financialResult, productResult, trendResult] = await Promise.all([
      client.rpc('get_financial_report', { p_start_date: start, p_end_date: end }),
      client.rpc('get_product_analytics', { p_start_date: start, p_end_date: end }),
      client.rpc('get_sales_recap', { p_start_date: start, p_end_date: end, p_period: group }),
    ])
    if (financialResult.error) throw financialResult.error
    if (productResult.error) throw productResult.error
    if (trendResult.error) throw trendResult.error
    if (requestId !== latestRequest) return
    financial.value = financialResult.data?.[0] ?? null
    products.value = productResult.data ?? []
    trend.value = trendResult.data ?? []
  } catch (error) {
    if (requestId === latestRequest) errorMessage.value = error.message || 'Laporan belum dapat dimuat.'
  } finally {
    if (requestId === latestRequest) loading.value = false
  }
}

function drillIntoPeriod(row) {
  const group = effectiveGroup.value
  let start = row.period_start
  let end = start
  if (group === 'week') end = addDays(start, 6)
  if (group === 'month') end = lastDayOfMonth(start)
  start = start > dateRange.value.start ? start : dateRange.value.start
  end = end < dateRange.value.end ? end : dateRange.value.end
  dateRange.value = { start, end }
  activePreset.value = 'custom'
  groupBy.value = 'day'
  loadReport()
}

function generatedAt() {
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'long',
    timeStyle: 'short',
    timeZone: 'Asia/Jakarta',
  }).format(new Date())
}

function exportPdf() {
  if (exporting.value || loading.value || errorMessage.value || validationMessage.value) return
  exporting.value = true
  try {
    downloadFinancialReportPdf({
      startDate: dateRange.value.start,
      endDate: dateRange.value.end,
      periodLabel: dateRangeLabel.value,
      groupBy: effectiveGroup.value,
      generatedAt: generatedAt(),
      summary: summary.value,
      trend: trend.value,
      products: topProducts.value,
    })
  } catch (error) {
    errorMessage.value = error.message || 'PDF laporan belum dapat dibuat.'
  } finally {
    exporting.value = false
  }
}

function exportCsv() {
  const rows = [
    ['Periode', 'Transaksi', 'Porsi', 'Omzet', 'HPP estimasi', 'Laba kotor', 'QRIS', 'Tunai', 'Jumlah ulasan', 'Rating rata-rata'],
    ...trend.value.map((row) => [
      periodLabel(row.period_start),
      row.transaction_count,
      row.portion_count,
      row.revenue,
      row.estimated_cogs,
      Number(row.revenue) - Number(row.estimated_cogs),
      row.qris_revenue,
      row.cash_revenue,
      row.review_count,
      row.review_count ? Number(row.average_rating).toFixed(1).replace('.', ',') : '',
    ]),
  ]
  const csv = `\uFEFF${rows.map((row) => row.map((cell) => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(';')).join('\r\n')}`
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = `rekap-penjualan-${dateRange.value.start}-${dateRange.value.end}.csv`
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

onMounted(loadReport)
</script>

<template>
  <section>
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Pembukuan</p>
        <h2 class="mt-1 text-xl font-black">Keuangan & penjualan</h2>
        <p class="mt-1 text-sm text-stone-500">Ringkasan, tren, menu, ulasan, dan rekap menggunakan filter tanggal yang sama.</p>
      </div>
      <div class="flex gap-2">
        <button class="rounded-xl border border-orange-200 bg-white px-4 py-2.5 text-sm font-bold text-chic-orange disabled:opacity-50" type="button" :disabled="loading || Boolean(errorMessage) || Boolean(validationMessage)" @click="exportCsv">Ekspor CSV</button>
        <button class="rounded-xl bg-chic-orange px-4 py-2.5 text-sm font-bold text-white disabled:bg-stone-300" type="button" :disabled="loading || exporting || Boolean(errorMessage) || Boolean(validationMessage)" @click="exportPdf">
          {{ exporting ? 'Membuat PDF…' : 'Ekspor laporan PDF' }}
        </button>
      </div>
    </div>

    <section class="mt-5 rounded-2xl border border-orange-100 bg-white p-4 shadow-sm">
      <div class="grid gap-3 md:grid-cols-[minmax(210px,0.7fr)_minmax(0,1.3fr)_auto] md:items-end">
        <label class="text-sm font-bold">Rentang waktu
          <select :value="activePreset" class="mt-1 w-full rounded-xl border border-stone-200 bg-white px-3 py-2.5" @change="choosePreset($event.target.value)">
            <option v-for="preset in datePresets" :key="preset.id" :value="preset.id">{{ preset.label }}</option>
            <option value="custom">Rentang khusus…</option>
          </select>
        </label>
        <div v-if="activePreset === 'custom'" class="grid gap-3 sm:grid-cols-2">
          <label class="text-sm font-bold">Dari
            <input v-model="dateRange.start" class="mt-1 w-full rounded-xl border border-stone-200 px-3 py-2.5" type="date">
          </label>
          <label class="text-sm font-bold">Sampai
            <input v-model="dateRange.end" class="mt-1 w-full rounded-xl border border-stone-200 px-3 py-2.5" type="date">
          </label>
        </div>
        <div v-else class="rounded-xl bg-orange-50 px-3 py-2.5 text-sm font-semibold text-stone-700">
          {{ dateRangeLabel }}
        </div>
        <button v-if="activePreset === 'custom'" class="rounded-xl bg-chic-orange px-4 py-2.5 text-sm font-bold text-white disabled:bg-stone-300" type="button" :disabled="loading" @click="loadReport">
          {{ loading ? 'Memuat…' : 'Terapkan' }}
        </button>
      </div>
      <div class="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-stone-500">
        <span>{{ dateRangeLabel }} · Grafik per {{ groupLabels[effectiveGroup] }}</span>
        <span>Omzet dan laba kotor hanya menghitung pesanan lunas.</span>
      </div>
      <div class="mt-3 border-t border-orange-100 pt-3">
        <button class="flex w-full items-center justify-between gap-3 text-left text-sm font-bold text-chic-orange" type="button" :aria-expanded="advancedFiltersOpen" aria-controls="advanced-report-filters" @click="advancedFiltersOpen = !advancedFiltersOpen">
          <span>Tampilan lanjutan</span>
          <span>{{ advancedFiltersOpen ? 'Tutup' : 'Atur pengelompokan' }}</span>
        </button>
        <div v-show="advancedFiltersOpen" id="advanced-report-filters" class="mt-3 grid gap-3 rounded-xl bg-stone-50 p-3 md:grid-cols-[minmax(200px,280px)_1fr] md:items-end">
          <label class="text-sm font-bold">Interval grafik & rekap
            <select :value="groupBy" class="mt-1 w-full rounded-xl border border-stone-200 bg-white px-3 py-2.5" @change="chooseGroup($event.target.value)">
              <option value="auto">Otomatis</option>
              <option value="day">Per hari</option>
              <option value="week">Per minggu</option>
              <option value="month">Per bulan</option>
            </select>
          </label>
          <p class="text-xs leading-relaxed text-stone-600">Pengelompokan hanya mengubah interval grafik dan baris rekap, bukan total. Otomatis memakai harian (≤31 hari), mingguan (32–180 hari), lalu bulanan (>180 hari).</p>
        </div>
      </div>
    </section>

    <p v-if="validationMessage" class="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">{{ validationMessage }}</p>
    <p v-if="errorMessage" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ errorMessage }}</p>

    <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <article v-for="card in [
        { label: 'Omzet', value: money(summary.revenue), tone: 'text-chic-orange' },
        { label: 'HPP estimasi', value: money(summary.estimatedCogs) },
        { label: 'Laba kotor estimasi', value: money(summary.grossProfit), tone: 'text-emerald-700', note: 'Sebelum biaya operasional' },
        { label: 'Margin kotor', value: `${summary.margin.toLocaleString('id-ID', { maximumFractionDigits: 1 })}%` },
        { label: 'Transaksi lunas', value: number(summary.transactionCount) },
        { label: 'Porsi terjual', value: number(summary.portionCount) },
        { label: 'Rata-rata transaksi', value: money(summary.averageTicket) },
        { label: 'Rating pelanggan', value: summary.reviewCount ? `${summary.averageRating.toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} / 5` : '—', note: `${number(summary.reviewCount)} ulasan` },
      ]" :key="card.label" class="rounded-2xl border border-orange-100 bg-white p-4 shadow-sm">
        <p class="text-xs font-bold uppercase tracking-wide text-stone-500">{{ card.label }}</p>
        <p class="mt-3 text-2xl font-black" :class="card.tone">{{ card.value }}</p>
        <p v-if="card.note" class="mt-1 text-xs text-stone-500">{{ card.note }}</p>
      </article>
    </div>

    <section class="mt-5 rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 class="font-black">Tren omzet</h3>
          <p class="mt-1 text-xs text-stone-500">Arahkan kursor untuk rincian. Klik batang untuk melihat periode tersebut per hari.</p>
        </div>
        <div v-if="selectedDetails" class="rounded-xl bg-orange-50 px-3 py-2 text-xs text-stone-700" aria-live="polite">
          <b class="text-chic-ink">{{ periodLabel(selectedDetails.period_start) }}</b>
          <span class="ml-2">Omzet {{ money(selectedDetails.revenue) }}</span>
          <span class="ml-2">{{ number(selectedDetails.transaction_count) }} transaksi</span>
          <span class="ml-2">{{ number(selectedDetails.portion_count) }} porsi</span>
          <span v-if="Number(selectedDetails.review_count)" class="ml-2">Rating {{ Number(selectedDetails.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) }}</span>
        </div>
      </div>
      <div v-if="chartRows.length" class="mt-5 overflow-x-auto pb-2">
        <div class="flex h-56 min-w-full items-end gap-1 border-b border-stone-200 px-1">
          <div
            v-for="(row, index) in chartRows"
            :key="row.period_start"
            class="group flex h-full min-w-8 flex-1 flex-col items-center justify-end"
          >
            <button
              class="w-full max-w-12 rounded-t-md bg-chic-orange transition-colors hover:bg-chic-orange-dark focus:bg-chic-orange-dark focus:outline-2 focus:outline-offset-2 focus:outline-chic-ink disabled:opacity-50"
              :style="{ height: `${Math.max(2, Number(row.revenue) / chartMax * 100)}%` }"
              :aria-label="`${periodLabel(row.period_start)}: omzet ${money(row.revenue)}, ${number(row.transaction_count)} transaksi, ${number(row.portion_count)} porsi. Klik untuk rincian harian.`"
              :disabled="loading"
              type="button"
              @mouseenter="hoveredPoint = row"
              @mouseleave="hoveredPoint = null"
              @focus="hoveredPoint = row"
              @blur="hoveredPoint = null"
              @click="drillIntoPeriod(row)"
            ></button>
            <span class="mt-2 h-4 whitespace-nowrap text-[10px] text-stone-500">{{ chartAxisLabel(row, index) }}</span>
          </div>
        </div>
      </div>
      <p v-else class="mt-6 rounded-xl bg-stone-50 p-6 text-center text-sm text-stone-500">{{ loading ? 'Memuat grafik…' : 'Belum ada transaksi lunas pada rentang ini.' }}</p>
    </section>

    <div class="mt-5 grid gap-5 lg:grid-cols-[0.8fr_1.2fr]">
      <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <h3 class="font-black">Metode pembayaran</h3>
        <p class="mt-1 text-xs text-stone-500">Proporsi dari total omzet lunas.</p>
        <div class="mt-5 space-y-5">
          <div v-for="payment in [
            { label: 'QRIS', value: summary.qrisRevenue, color: 'bg-chic-orange' },
            { label: 'Tunai', value: summary.cashRevenue, color: 'bg-amber-500' },
          ]" :key="payment.label">
            <div class="flex justify-between text-sm font-bold"><span>{{ payment.label }}</span><span>{{ money(payment.value) }}</span></div>
            <div class="mt-2 h-3 overflow-hidden rounded-full bg-stone-100"><div class="h-full rounded-full transition-all" :class="payment.color" :style="{ width: `${summary.revenue ? payment.value / summary.revenue * 100 : 0}%` }"></div></div>
            <p class="mt-1 text-right text-xs text-stone-500">{{ summary.revenue ? Math.round(payment.value / summary.revenue * 100) : 0 }}%</p>
          </div>
        </div>
      </section>

      <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <div class="flex items-center justify-between gap-3"><h3 class="font-black">Menu terlaris</h3><span class="text-xs text-stone-500">Periode terpilih</span></div>
        <div v-if="topProducts.length" class="mt-3 divide-y divide-stone-100">
          <article v-for="(item, index) in topProducts" :key="`${item.size}-${item.sauce_variant}-${item.carb_type}`" class="flex items-center gap-3 py-3">
            <span class="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-orange-50 text-xs font-black text-chic-orange">{{ index + 1 }}</span>
            <span class="min-w-0 flex-1 truncate text-sm font-bold">{{ item.label }}</span>
            <span class="text-xs text-stone-500">{{ number(item.total_qty) }} porsi</span>
            <b class="text-sm">{{ money(item.total_sales) }}</b>
          </article>
        </div>
        <p v-else class="mt-5 rounded-xl bg-stone-50 p-5 text-center text-sm text-stone-500">{{ loading ? 'Memuat menu…' : 'Belum ada penjualan pada rentang ini.' }}</p>
      </section>
    </div>

    <section class="mt-5 overflow-hidden rounded-2xl border border-orange-100 bg-white shadow-sm">
      <div class="flex flex-wrap items-end justify-between gap-3 p-5">
        <div><h3 class="font-black">Rekap penjualan</h3><p class="mt-1 text-xs text-stone-500">{{ trend.length }} periode · {{ dateRangeLabel }}</p></div>
        <p class="text-sm font-bold text-emerald-700">Laba kotor: {{ money(summary.grossProfit) }}</p>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[980px] text-left text-sm">
          <thead class="bg-orange-50 text-xs uppercase text-stone-500">
            <tr>
              <th class="px-4 py-3">Periode</th><th class="px-4 py-3 text-right">Transaksi</th><th class="px-4 py-3 text-right">Porsi</th>
              <th class="px-4 py-3 text-right">Omzet</th><th class="px-4 py-3 text-right">HPP</th><th class="px-4 py-3 text-right">Laba kotor</th>
              <th class="px-4 py-3 text-right">QRIS</th><th class="px-4 py-3 text-right">Tunai</th><th class="px-4 py-3 text-right">Ulasan</th><th class="px-4 py-3 text-right">Rating</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-stone-100">
            <tr v-for="row in trend" :key="row.period_start">
              <td class="whitespace-nowrap px-4 py-3 font-bold">{{ periodLabel(row.period_start) }}</td>
              <td class="px-4 py-3 text-right">{{ number(row.transaction_count) }}</td><td class="px-4 py-3 text-right">{{ number(row.portion_count) }}</td>
              <td class="px-4 py-3 text-right font-bold">{{ money(row.revenue) }}</td><td class="px-4 py-3 text-right">{{ money(row.estimated_cogs) }}</td>
              <td class="px-4 py-3 text-right font-bold text-emerald-700">{{ money(Number(row.revenue) - Number(row.estimated_cogs)) }}</td>
              <td class="px-4 py-3 text-right">{{ money(row.qris_revenue) }}</td><td class="px-4 py-3 text-right">{{ money(row.cash_revenue) }}</td>
              <td class="px-4 py-3 text-right">{{ number(row.review_count) }}</td>
              <td class="px-4 py-3 text-right">{{ Number(row.review_count) ? Number(row.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : '—' }}</td>
            </tr>
            <tr v-if="!trend.length"><td colspan="10" class="px-4 py-8 text-center text-stone-500">{{ loading ? 'Memuat rekap…' : 'Belum ada transaksi lunas pada rentang ini.' }}</td></tr>
          </tbody>
          <tfoot v-if="trend.length" class="border-t-2 border-orange-100 bg-orange-50 font-black">
            <tr>
              <td class="px-4 py-3">Total</td><td class="px-4 py-3 text-right">{{ number(summary.transactionCount) }}</td><td class="px-4 py-3 text-right">{{ number(summary.portionCount) }}</td>
              <td class="px-4 py-3 text-right">{{ money(summary.revenue) }}</td><td class="px-4 py-3 text-right">{{ money(summary.estimatedCogs) }}</td>
              <td class="px-4 py-3 text-right text-emerald-700">{{ money(summary.grossProfit) }}</td><td class="px-4 py-3 text-right">{{ money(summary.qrisRevenue) }}</td>
              <td class="px-4 py-3 text-right">{{ money(summary.cashRevenue) }}</td><td class="px-4 py-3 text-right">{{ number(summary.reviewCount) }}</td>
              <td class="px-4 py-3 text-right">{{ summary.reviewCount ? summary.averageRating.toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : '—' }}</td>
            </tr>
          </tfoot>
        </table>
      </div>
      <p class="border-t border-orange-100 px-5 py-3 text-xs text-stone-500">HPP memakai harga bahan pada saat pesanan dibuat. Laba kotor belum dikurangi biaya operasional.</p>
    </section>
  </section>
</template>
