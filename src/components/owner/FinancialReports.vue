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
const timeFormatter = new Intl.DateTimeFormat('id-ID', {
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'Asia/Jakarta',
})

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
const previousFinancial = ref(null)
const products = ref([])
const trend = ref([])
const hourlyTrend = ref([])
const transactionRows = ref([])
const recapMode = ref('hour')
const chartMetricOverride = ref(null)
const paymentChartType = ref('bar')
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
const isSingleDayReport = computed(() => effectiveGroup.value === 'day' && dateRange.value.start === dateRange.value.end)
const summaryFrom = (financialRow, rows) => {
  const revenue = Number(financialRow?.revenue ?? 0)
  const estimatedCogs = rows.reduce((sum, row) => sum + Number(row.estimated_cogs), 0)
  const reviewCount = rows.reduce((sum, row) => sum + Number(row.review_count), 0)
  const ratingTotal = rows.reduce((sum, row) => sum + Number(row.average_rating) * Number(row.review_count), 0)
  const portionCount = rows.reduce((sum, row) => sum + Number(row.portion_count), 0)
  const transactionCount = Number(financialRow?.transaction_count ?? 0)
  const grossProfit = revenue - estimatedCogs
  return {
    revenue,
    estimatedCogs,
    grossProfit,
    margin: revenue ? grossProfit / revenue * 100 : 0,
    transactionCount,
    portionCount,
    averageTicket: transactionCount ? revenue / transactionCount : 0,
    cashRevenue: Number(financialRow?.cash_revenue ?? 0),
    qrisRevenue: Number(financialRow?.qris_revenue ?? 0),
    reviewCount,
    averageRating: reviewCount ? ratingTotal / reviewCount : 0,
  }
}
const summary = computed(() => summaryFrom(financial.value, trend.value))
const previousSummary = computed(() => previousFinancial.value
  ? summaryFrom(previousFinancial.value.financial, previousFinancial.value.trend)
  : null)
const previousRangeLabel = computed(() => {
  const days = daysBetween(dateRange.value.start, dateRange.value.end)
  return `${formatDate(addDays(dateRange.value.start, -days))} – ${formatDate(addDays(dateRange.value.start, -1))}`
})
const chartMetric = computed(() => chartMetricOverride.value ?? (isSingleDayReport.value ? 'transactions' : 'revenue'))
const chartValue = (row) => Number(chartMetric.value === 'transactions' ? row.transaction_count : row.revenue)
const hourLabel = (row) => `${row.period_start.slice(11, 13)}.00–${String(Number(row.period_start.slice(11, 13)) + 1).padStart(2, '0')}.00`
const hourlyChartRows = computed(() => Array.from({ length: 12 }, (_, index) => {
  const hour = String(index + 9).padStart(2, '0')
  const existing = hourlyTrend.value.find((row) => row.period_start.slice(11, 13) === hour)
  return existing ?? {
    period_start: `${dateRange.value.start}T${hour}:00:00`,
    revenue: 0,
    estimated_cogs: 0,
    transaction_count: 0,
    portion_count: 0,
    cash_revenue: 0,
    qris_revenue: 0,
    average_rating: 0,
    review_count: 0,
  }
}))
const chartRows = computed(() => isSingleDayReport.value ? hourlyChartRows.value : [...trend.value].reverse())
const chartMax = computed(() => {
  const maximum = Math.max(0, ...chartRows.value.map(chartValue))
  if (chartMetric.value === 'transactions') return Math.max(5, Math.ceil(maximum / 5) * 5)
  const roughStep = Math.max(1, maximum) / 5
  const magnitude = 10 ** Math.floor(Math.log10(roughStep))
  const normalizedStep = roughStep / magnitude
  const step = (normalizedStep <= 1 ? 1 : normalizedStep <= 2 ? 2 : normalizedStep <= 5 ? 5 : 10) * magnitude
  return step * 5
})
const chartTicks = computed(() => Array.from({ length: 6 }, (_, index) => chartMax.value * (5 - index) / 5))
const selectedDetails = computed(() => hoveredPoint.value || selectedPoint.value)
const yAxisLabel = computed(() => chartMetric.value === 'transactions' ? 'Jumlah transaksi' : 'Omzet (Rp)')
const hoverTooltipStyle = computed(() => {
  if (!selectedDetails.value || !chartRows.value.length) return {}
  const selectedIndex = chartRows.value.findIndex((row) => row.period_start === selectedDetails.value.period_start)
  const horizontalPosition = selectedIndex < 0
    ? 50
    : (selectedIndex + 0.5) / chartRows.value.length * 100
  const maximum = Math.max(...chartRows.value.map(chartValue))
  const topPosition = maximum ? Math.max(0, (1 - maximum / chartMax.value) * 100) : 0
  let horizontalAlignment = 'translateX(-50%)'
  if (chartRows.value.length === 2) {
    horizontalAlignment = selectedIndex === 0 ? 'translateX(0)' : 'translateX(-100%)'
  } else if (chartRows.value.length > 2) {
    if (selectedIndex < chartRows.value.length * 0.35) horizontalAlignment = 'translateX(0)'
    else if (selectedIndex >= chartRows.value.length * 0.65) horizontalAlignment = 'translateX(-100%)'
  }
  return {
    left: `${horizontalPosition}%`,
    top: `${topPosition}%`,
    transform: `${horizontalAlignment} translateY(calc(-100% - 8px))`,
  }
})
const paymentDonutStyle = computed(() => {
  const qrisShare = summary.value.revenue ? summary.value.qrisRevenue / summary.value.revenue * 100 : 0
  return {
    background: summary.value.revenue
      ? `conic-gradient(var(--color-chic-orange) 0 ${qrisShare}%, #f59e0b ${qrisShare}% 100%)`
      : '#e7e5e4',
  }
})
const topProducts = computed(() => products.value.slice(0, 10).map((item) => ({
  ...item,
  label: `${getSize(item.size)?.label ?? item.size} · ${getSauce(item.sauce_variant)?.label ?? item.sauce_variant} · ${getCarb(item.carb_type)?.label ?? item.carb_type}`,
})))
const kpiCards = computed(() => {
  const current = summary.value
  const previous = previousSummary.value
  return [
    { key: 'revenue', metric: 'revenue', label: 'Omzet', value: money(current.revenue), tone: 'text-chic-orange' },
    { key: 'cogs', metric: 'estimatedCogs', label: 'HPP estimasi', value: money(current.estimatedCogs), lowerIsBetter: true },
    { key: 'profit', metric: 'grossProfit', label: 'Laba kotor estimasi', value: money(current.grossProfit), tone: 'text-emerald-700', note: 'Sebelum biaya operasional' },
    { key: 'margin', metric: 'margin', label: 'Margin kotor', value: `${current.margin.toLocaleString('id-ID', { maximumFractionDigits: 1 })}%`, points: true },
    { key: 'transactions', metric: 'transactionCount', label: 'Transaksi lunas', value: number(current.transactionCount) },
    { key: 'portions', metric: 'portionCount', label: 'Porsi terjual', value: number(current.portionCount) },
    { key: 'ticket', metric: 'averageTicket', label: 'Rata-rata transaksi', value: money(current.averageTicket) },
    {
      key: 'rating',
      metric: 'averageRating',
      label: 'Rating pelanggan',
      value: current.reviewCount ? `${current.averageRating.toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} / 5` : '—',
      points: true,
      note: `${number(current.reviewCount)} ulasan`,
    },
  ].map((card) => ({
    ...card,
    delta: previous ? formatDelta(current[card.metric], previous[card.metric], {
      lowerIsBetter: card.lowerIsBetter,
      points: card.points,
    }) : null,
  }))
})

function formatDelta(currentValue, previousValue, { lowerIsBetter = false, points = false } = {}) {
  const current = Number(currentValue ?? 0)
  const previous = Number(previousValue ?? 0)
  const difference = current - previous
  const improved = lowerIsBetter ? difference < 0 : difference > 0
  if (!previous) {
    if (!current) return { arrow: '•', label: 'Tidak ada perubahan', tone: 'text-stone-500' }
    const improved = lowerIsBetter ? current < 0 : current > 0
    return {
      arrow: current > 0 ? '▲' : '▼',
      label: 'Baru',
      tone: improved ? 'text-emerald-700' : 'text-rose-700',
    }
  }
  if (!difference) return { arrow: '•', label: points ? '0,0 poin' : '0%', tone: 'text-stone-500' }
  const change = points
    ? `${difference > 0 ? '+' : '−'}${Math.abs(difference).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} poin`
    : `${Math.abs(difference / Math.abs(previous) * 100).toLocaleString('id-ID', { maximumFractionDigits: 1 })}%`
  return {
    arrow: difference > 0 ? '▲' : '▼',
    label: change,
    tone: improved ? 'text-emerald-700' : 'text-rose-700',
  }
}

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
  if (isSingleDayReport.value) return row.period_start.slice(11, 13)
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

function chartPeriodLabel(row) {
  return isSingleDayReport.value ? hourLabel(row) : periodLabel(row.period_start)
}

function chartValueText(row) {
  return chartMetric.value === 'transactions'
    ? `${number(row.transaction_count)} transaksi`
    : money(row.revenue)
}

function chartTickLabel(value) {
  if (chartMetric.value === 'transactions') return number(value)
  if (value >= 1000000) return `Rp${(value / 1000000).toLocaleString('id-ID', { maximumFractionDigits: 1 })} jt`
  if (value >= 1000) return `Rp${(value / 1000).toLocaleString('id-ID', { maximumFractionDigits: 1 })} rb`
  return money(value)
}

const xAxisLabel = computed(() => isSingleDayReport.value
  ? 'Jam'
  : effectiveGroup.value === 'month' ? 'Bulan' : effectiveGroup.value === 'week' ? 'Minggu' : 'Tanggal')

function transactionTime(value) {
  return timeFormatter.format(new Date(value))
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
  hoveredPoint.value = null
  selectedPoint.value = null
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
  chartMetricOverride.value = null
  try {
    const client = requireSupabase()
    const start = dateRange.value.start
    const end = dateRange.value.end
    const group = effectiveGroup.value
    const rangeDays = daysBetween(start, end)
    const previousStart = addDays(start, -rangeDays)
    const previousEnd = addDays(start, -1)
    const singleDay = group === 'day' && rangeDays === 1
    const [financialResult, productResult, trendResult, previousFinancialResult, previousTrendResult, hourlyResult, transactionResult] = await Promise.all([
      client.rpc('get_financial_report', { p_start_date: start, p_end_date: end }),
      client.rpc('get_product_analytics', { p_start_date: start, p_end_date: end }),
      client.rpc('get_sales_recap', { p_start_date: start, p_end_date: end, p_period: group }),
      client.rpc('get_financial_report', { p_start_date: previousStart, p_end_date: previousEnd }),
      client.rpc('get_sales_recap', { p_start_date: previousStart, p_end_date: previousEnd, p_period: 'day' }),
      singleDay ? client.rpc('get_hourly_sales_recap', { p_business_date: start }) : Promise.resolve({ data: [], error: null }),
      singleDay ? client.rpc('get_transaction_sales_recap', { p_business_date: start }) : Promise.resolve({ data: [], error: null }),
    ])
    if (financialResult.error) throw financialResult.error
    if (productResult.error) throw productResult.error
    if (trendResult.error) throw trendResult.error
    if (previousFinancialResult.error) throw previousFinancialResult.error
    if (previousTrendResult.error) throw previousTrendResult.error
    if (hourlyResult.error) throw hourlyResult.error
    if (transactionResult.error) throw transactionResult.error
    if (requestId !== latestRequest) return
    financial.value = financialResult.data?.[0] ?? null
    previousFinancial.value = {
      financial: previousFinancialResult.data?.[0] ?? null,
      trend: previousTrendResult.data ?? [],
    }
    products.value = productResult.data ?? []
    trend.value = trendResult.data ?? []
    hourlyTrend.value = hourlyResult.data ?? []
    transactionRows.value = transactionResult.data ?? []
    recapMode.value = 'hour'
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

function selectChartRow(row) {
  if (isSingleDayReport.value) {
    selectedPoint.value = row
    return
  }
  drillIntoPeriod(row)
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
      isSingleDay: isSingleDayReport.value,
      chartMetric: chartMetric.value,
      detailMode: recapMode.value,
      hourlyTrend: hourlyChartRows.value,
      transactions: transactionRows.value,
    })
  } catch (error) {
    errorMessage.value = error.message || 'PDF laporan belum dapat dibuat.'
  } finally {
    exporting.value = false
  }
}

function exportCsv() {
  let rows
  if (isSingleDayReport.value && recapMode.value === 'transaction') {
    rows = [
      ['Jam', 'Nomor antrean', 'Metode pembayaran', 'Porsi', 'Omzet', 'HPP estimasi', 'Laba kotor', 'Rating'],
      ...transactionRows.value.map((row) => [
        transactionTime(row.created_at),
        row.queue_number,
        row.payment_method === 'qris' ? 'QRIS' : 'Tunai',
        row.portion_count,
        row.revenue,
        row.estimated_cogs,
        Number(row.revenue) - Number(row.estimated_cogs),
        row.review_rating ?? '',
      ]),
    ]
  } else if (isSingleDayReport.value) {
    rows = [
      ['Jam', 'Transaksi', 'Porsi', 'Omzet', 'HPP estimasi', 'Laba kotor', 'QRIS', 'Tunai', 'Jumlah ulasan', 'Rating rata-rata'],
      ...hourlyChartRows.value.map((row) => [
        hourLabel(row),
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
  } else {
    rows = [
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
  }
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

    <p v-if="previousSummary" class="mt-4 text-xs text-stone-500">Indikator dibandingkan dengan {{ previousRangeLabel }} (rentang sebelumnya yang sama panjang).</p>
    <div class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <article v-for="card in kpiCards" :key="card.key" class="rounded-2xl border border-orange-100 bg-white p-4 shadow-sm">
        <p class="text-xs font-bold uppercase tracking-wide text-stone-500">{{ card.label }}</p>
        <p class="mt-3 text-2xl font-black" :class="card.tone">{{ card.value }}</p>
        <p v-if="card.note" class="mt-1 text-xs text-stone-500">{{ card.note }}</p>
        <p v-if="card.delta" class="mt-2 flex items-center gap-1 text-xs font-bold" :class="card.delta.tone" :aria-label="`Perubahan ${card.delta.label} dibanding periode sebelumnya`">
          <span aria-hidden="true">{{ card.delta.arrow }}</span>{{ card.delta.label }}
        </p>
      </article>
    </div>

    <section class="relative mt-5 rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 class="font-black">{{ isSingleDayReport ? (chartMetric === 'transactions' ? 'Frekuensi transaksi per jam' : 'Omzet per jam') : (chartMetric === 'transactions' ? 'Frekuensi transaksi' : 'Tren omzet') }}</h3>
          <p class="mt-1 text-xs text-stone-500">{{ isSingleDayReport ? `Rincian ${formatDate(dateRange.start)} · klik/arah kursor pada batang untuk detail.` : 'Arahkan kursor untuk rincian. Klik batang untuk membuka tanggal tersebut.' }}</p>
        </div>
        <div class="flex gap-1 rounded-xl bg-stone-100 p-1" aria-label="Metrik grafik">
          <button v-for="metric in [{ id: 'transactions', label: 'Transaksi' }, { id: 'revenue', label: 'Omzet' }]" :key="metric.id" class="rounded-lg px-3 py-1.5 text-xs font-bold" :class="chartMetric === metric.id ? 'bg-white text-chic-ink shadow-sm' : 'text-stone-500'" type="button" @click="chartMetricOverride = metric.id">{{ metric.label }}</button>
        </div>
      </div>
      <div v-if="chartRows.length && (!isSingleDayReport || summary.transactionCount)" class="mt-5 overflow-x-auto pb-2">
        <div class="mt-12 min-w-full" :style="{ minWidth: `${Math.max(416, chartRows.length * 36 + 64)}px` }">
          <div class="relative mt-2 h-48">
            <span class="absolute left-0 top-1/2 -translate-y-1/2 -rotate-180 text-[10px] font-medium text-stone-600" style="writing-mode: vertical-rl">{{ yAxisLabel }}</span>
            <div class="pointer-events-none absolute inset-y-0 left-16 border-l border-stone-300/60"></div>
            <div class="pointer-events-none absolute inset-0 flex flex-col justify-between pl-16">
              <div v-for="tick in chartTicks" :key="tick" class="relative border-t border-stone-300/60">
                <span class="absolute -left-12 top-0 w-10 -translate-y-1/2 pr-1 text-right text-[10px] leading-none text-stone-500">{{ chartTickLabel(tick) }}</span>
              </div>
            </div>
            <div class="absolute inset-y-0 left-16 right-0 flex items-end gap-1 px-1">
              <div
                v-for="row in chartRows"
                :key="row.period_start"
                class="group flex h-full min-w-8 flex-1 flex-col items-center justify-end"
              >
                <button
                  class="w-full max-w-12 rounded-t-md bg-chic-orange transition-colors hover:bg-chic-orange-dark focus:bg-chic-orange-dark focus:outline-2 focus:outline-offset-2 focus:outline-chic-ink disabled:opacity-50"
                  :class="chartValue(row) ? '' : 'opacity-30'"
                  :style="{ height: `${chartValue(row) / chartMax * 100}%` }"
                  :aria-label="`${chartPeriodLabel(row)}: ${chartValueText(row)}, omzet ${money(row.revenue)}, ${number(row.transaction_count)} transaksi, ${number(row.portion_count)} porsi.${isSingleDayReport ? '' : ' Klik untuk rincian per jam.'}`"
                  :disabled="loading"
                  type="button"
                  @mouseenter="hoveredPoint = row"
                  @mouseleave="hoveredPoint = null"
                  @focus="hoveredPoint = row"
                  @blur="hoveredPoint = null"
                  @click="selectChartRow(row)"
                ></button>
              </div>
            </div>
            <div v-if="selectedDetails" class="pointer-events-none absolute z-20 max-w-64 rounded-xl border border-orange-100 bg-white/95 px-3 py-2 text-xs text-stone-700 shadow-lg backdrop-blur-sm" :style="hoverTooltipStyle" aria-live="polite">
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <b class="text-chic-ink">{{ chartPeriodLabel(selectedDetails) }}</b>
                <span>Omzet {{ money(selectedDetails.revenue) }}</span>
                <span>{{ number(selectedDetails.transaction_count) }} transaksi</span>
                <span>{{ number(selectedDetails.portion_count) }} porsi</span>
                <span v-if="Number(selectedDetails.review_count)">Rating {{ Number(selectedDetails.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) }}</span>
              </div>
            </div>
          </div>
          <div class="ml-16 flex gap-1 px-1">
            <div
              v-for="(row, index) in chartRows"
              :key="row.period_start"
              class="min-w-8 flex-1 text-center"
            >
              <span class="whitespace-nowrap text-[10px] text-stone-500">{{ chartAxisLabel(row, index) }}</span>
            </div>
          </div>
          <p class="ml-16 mt-1 text-center text-[10px] font-medium text-stone-600">{{ xAxisLabel }}</p>
        </div>
      </div>
      <p v-else class="mt-6 rounded-xl bg-stone-50 p-6 text-center text-sm text-stone-500">{{ loading ? 'Memuat grafik…' : 'Belum ada transaksi lunas pada rentang ini.' }}</p>
    </section>

    <div class="mt-5 grid gap-5 lg:grid-cols-[0.8fr_1.2fr]">
      <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div><h3 class="font-black">Metode pembayaran</h3><p class="mt-1 text-xs text-stone-500">Proporsi dari total omzet lunas.</p></div>
          <div class="flex gap-1 rounded-xl bg-stone-100 p-1" aria-label="Tampilan metode pembayaran">
            <button class="rounded-lg p-2" :class="paymentChartType === 'bar' ? 'bg-white text-chic-ink shadow-sm' : 'text-stone-500'" type="button" aria-label="Tampilan batang" title="Tampilan batang" :aria-pressed="paymentChartType === 'bar'" @click="paymentChartType = 'bar'">
              <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
                <path d="M4 6h7M4 12h12M4 18h16" />
              </svg>
            </button>
            <button class="rounded-lg p-2" :class="paymentChartType === 'donut' ? 'bg-white text-chic-ink shadow-sm' : 'text-stone-500'" type="button" aria-label="Tampilan donat" title="Tampilan donat" :aria-pressed="paymentChartType === 'donut'" @click="paymentChartType = 'donut'">
              <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <circle cx="12" cy="12" r="8.5" />
                <circle cx="12" cy="12" r="3.5" />
                <path d="M12 3.5V8.5M20.5 12h-5" />
              </svg>
            </button>
          </div>
        </div>
        <div v-if="paymentChartType === 'bar'" class="mt-5 space-y-5">
          <div v-for="payment in [
            { label: 'QRIS', value: summary.qrisRevenue, color: 'bg-chic-orange' },
            { label: 'Tunai', value: summary.cashRevenue, color: 'bg-amber-500' },
          ]" :key="payment.label">
            <div class="flex justify-between text-sm font-bold"><span>{{ payment.label }}</span><span>{{ money(payment.value) }}</span></div>
            <div class="mt-2 h-3 overflow-hidden rounded-full bg-stone-100"><div class="h-full rounded-full transition-all" :class="payment.color" :style="{ width: `${summary.revenue ? payment.value / summary.revenue * 100 : 0}%` }"></div></div>
            <p class="mt-1 text-right text-xs text-stone-500">{{ summary.revenue ? Math.round(payment.value / summary.revenue * 100) : 0 }}%</p>
          </div>
        </div>
        <div v-else class="mt-5 flex flex-wrap items-center justify-center gap-6">
          <div class="grid h-40 w-40 shrink-0 place-items-center rounded-full" :style="paymentDonutStyle" role="img" :aria-label="`QRIS ${summary.revenue ? Math.round(summary.qrisRevenue / summary.revenue * 100) : 0} persen, tunai ${summary.revenue ? Math.round(summary.cashRevenue / summary.revenue * 100) : 0} persen`">
            <div class="grid h-24 w-24 place-content-center rounded-full bg-white text-center shadow-inner">
              <span class="text-[10px] font-bold uppercase text-stone-500">Total omzet</span>
              <b class="text-sm">{{ money(summary.revenue) }}</b>
            </div>
          </div>
          <div class="space-y-3 text-sm">
            <p class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-chic-orange"></span><span class="font-bold">QRIS</span><span>{{ money(summary.qrisRevenue) }} · {{ summary.revenue ? Math.round(summary.qrisRevenue / summary.revenue * 100) : 0 }}%</span></p>
            <p class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-amber-500"></span><span class="font-bold">Tunai</span><span>{{ money(summary.cashRevenue) }} · {{ summary.revenue ? Math.round(summary.cashRevenue / summary.revenue * 100) : 0 }}%</span></p>
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
        <div>
          <h3 class="font-black">Rekap penjualan</h3>
          <p class="mt-1 text-xs text-stone-500">{{ isSingleDayReport ? (recapMode === 'hour' ? 'Rincian per jam' : `${transactionRows.length} transaksi`) : `${trend.length} periode` }} · {{ dateRangeLabel }}</p>
        </div>
        <p class="text-sm font-bold text-emerald-700">Laba kotor: {{ money(summary.grossProfit) }}</p>
        <div v-if="isSingleDayReport" class="flex gap-1 rounded-xl bg-stone-100 p-1" aria-label="Rincian rekap harian">
          <button v-for="mode in [{ id: 'hour', label: 'Per jam' }, { id: 'transaction', label: 'Per transaksi' }]" :key="mode.id" class="rounded-lg px-3 py-1.5 text-xs font-bold" :class="recapMode === mode.id ? 'bg-white text-chic-ink shadow-sm' : 'text-stone-500'" type="button" @click="recapMode = mode.id">{{ mode.label }}</button>
        </div>
      </div>
      <div class="overflow-x-auto">
        <table v-if="isSingleDayReport && recapMode === 'transaction'" class="w-full min-w-[820px] text-left text-sm">
          <thead class="bg-orange-50 text-xs uppercase text-stone-500">
            <tr>
              <th class="px-4 py-3">Waktu</th><th class="px-4 py-3">Antrean</th><th class="px-4 py-3">Pembayaran</th><th class="px-4 py-3 text-right">Porsi</th>
              <th class="px-4 py-3 text-right">Omzet</th><th class="px-4 py-3 text-right">HPP</th><th class="px-4 py-3 text-right">Laba kotor</th><th class="px-4 py-3 text-right">Rating</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-stone-100">
            <tr v-for="row in transactionRows" :key="row.order_id">
              <td class="whitespace-nowrap px-4 py-3">{{ transactionTime(row.created_at) }}</td>
              <td class="px-4 py-3 font-bold">#{{ row.queue_number }}</td>
              <td class="px-4 py-3">{{ row.payment_method === 'qris' ? 'QRIS' : 'Tunai' }}</td>
              <td class="px-4 py-3 text-right">{{ number(row.portion_count) }}</td>
              <td class="px-4 py-3 text-right font-bold">{{ money(row.revenue) }}</td>
              <td class="px-4 py-3 text-right">{{ money(row.estimated_cogs) }}</td>
              <td class="px-4 py-3 text-right font-bold text-emerald-700">{{ money(Number(row.revenue) - Number(row.estimated_cogs)) }}</td>
              <td class="px-4 py-3 text-right">{{ row.review_rating ?? '—' }}</td>
            </tr>
            <tr v-if="!transactionRows.length"><td colspan="8" class="px-4 py-8 text-center text-stone-500">{{ loading ? 'Memuat transaksi…' : 'Belum ada transaksi lunas pada tanggal ini.' }}</td></tr>
          </tbody>
          <tfoot v-if="transactionRows.length" class="border-t-2 border-orange-100 bg-orange-50 font-black">
            <tr>
              <td colspan="3" class="px-4 py-3">Total · {{ number(summary.transactionCount) }} transaksi</td>
              <td class="px-4 py-3 text-right">{{ number(summary.portionCount) }}</td><td class="px-4 py-3 text-right">{{ money(summary.revenue) }}</td>
              <td class="px-4 py-3 text-right">{{ money(summary.estimatedCogs) }}</td><td class="px-4 py-3 text-right text-emerald-700">{{ money(summary.grossProfit) }}</td>
              <td class="px-4 py-3 text-right">{{ summary.reviewCount ? summary.averageRating.toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : '—' }}</td>
            </tr>
          </tfoot>
        </table>
        <table v-else-if="isSingleDayReport" class="w-full min-w-[980px] text-left text-sm">
          <thead class="bg-orange-50 text-xs uppercase text-stone-500">
            <tr>
              <th class="px-4 py-3">Jam</th><th class="px-4 py-3 text-right">Transaksi</th><th class="px-4 py-3 text-right">Porsi</th>
              <th class="px-4 py-3 text-right">Omzet</th><th class="px-4 py-3 text-right">HPP</th><th class="px-4 py-3 text-right">Laba kotor</th>
              <th class="px-4 py-3 text-right">QRIS</th><th class="px-4 py-3 text-right">Tunai</th><th class="px-4 py-3 text-right">Ulasan</th><th class="px-4 py-3 text-right">Rating</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-stone-100">
            <tr v-for="row in hourlyChartRows" :key="row.period_start">
              <td class="whitespace-nowrap px-4 py-3 font-bold">{{ hourLabel(row) }}</td>
              <td class="px-4 py-3 text-right">{{ number(row.transaction_count) }}</td><td class="px-4 py-3 text-right">{{ number(row.portion_count) }}</td>
              <td class="px-4 py-3 text-right font-bold">{{ money(row.revenue) }}</td><td class="px-4 py-3 text-right">{{ money(row.estimated_cogs) }}</td>
              <td class="px-4 py-3 text-right font-bold text-emerald-700">{{ money(Number(row.revenue) - Number(row.estimated_cogs)) }}</td>
              <td class="px-4 py-3 text-right">{{ money(row.qris_revenue) }}</td><td class="px-4 py-3 text-right">{{ money(row.cash_revenue) }}</td>
              <td class="px-4 py-3 text-right">{{ number(row.review_count) }}</td>
              <td class="px-4 py-3 text-right">{{ Number(row.review_count) ? Number(row.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : '—' }}</td>
            </tr>
          </tbody>
          <tfoot class="border-t-2 border-orange-100 bg-orange-50 font-black">
            <tr>
              <td class="px-4 py-3">Total</td><td class="px-4 py-3 text-right">{{ number(summary.transactionCount) }}</td><td class="px-4 py-3 text-right">{{ number(summary.portionCount) }}</td>
              <td class="px-4 py-3 text-right">{{ money(summary.revenue) }}</td><td class="px-4 py-3 text-right">{{ money(summary.estimatedCogs) }}</td>
              <td class="px-4 py-3 text-right text-emerald-700">{{ money(summary.grossProfit) }}</td><td class="px-4 py-3 text-right">{{ money(summary.qrisRevenue) }}</td>
              <td class="px-4 py-3 text-right">{{ money(summary.cashRevenue) }}</td><td class="px-4 py-3 text-right">{{ number(summary.reviewCount) }}</td>
              <td class="px-4 py-3 text-right">{{ summary.reviewCount ? summary.averageRating.toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : '—' }}</td>
            </tr>
          </tfoot>
        </table>
        <table v-else class="w-full min-w-[980px] text-left text-sm">
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
