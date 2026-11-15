import { jsPDF } from 'jspdf'

const PAGE_MARGIN = 14
const ORANGE = [239, 116, 38]
const INK = [43, 27, 18]
const MUTED = [105, 97, 90]
const PALE = [255, 246, 237]
const LINE = [232, 224, 216]
const currency = (value) => `Rp${Math.round(Number(value ?? 0)).toLocaleString('id-ID')}`
const number = (value) => Number(value ?? 0).toLocaleString('id-ID')
const dateFormatter = new Intl.DateTimeFormat('id-ID', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC',
})
const monthFormatter = new Intl.DateTimeFormat('id-ID', {
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
})
const formatDate = (date) => dateFormatter.format(date)
const utcDate = (value) => new Date(`${value}T00:00:00Z`)
const addUtcDays = (date, days) => {
  const result = new Date(date)
  result.setUTCDate(result.getUTCDate() + days)
  return result
}

function periodLabel(value, groupBy) {
  const start = utcDate(value)
  if (groupBy === 'month') return monthFormatter.format(start)
  if (groupBy === 'week') {
    const end = addUtcDays(start, 6)
    return `${dateFormatter.format(start)} - ${dateFormatter.format(end)}`
  }
  return dateFormatter.format(start)
}

function chartPoints(rows, groupBy) {
  if (rows.length <= 24) {
    return rows.map((row) => ({
      label: periodLabel(row.period_start, groupBy),
      value: Number(row.revenue),
    }))
  }

  const bucketSize = Math.ceil(rows.length / 24)
  const points = []
  for (let index = 0; index < rows.length; index += bucketSize) {
    const bucket = rows.slice(index, index + bucketSize)
    const first = utcDate(bucket[0].period_start)
    const last = utcDate(bucket[bucket.length - 1].period_start)
    points.push({
      label: `${dateFormatter.format(first)} - ${dateFormatter.format(last)}`,
      value: bucket.reduce((sum, row) => sum + Number(row.revenue), 0),
    })
  }
  return points
}

function chartTime(value) {
  return new Intl.DateTimeFormat('id-ID', {
    hour: '2-digit',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(value))
}

export function createFinancialReportPdf(report) {
  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4', compress: true })
  const pageWidth = doc.internal.pageSize.getWidth()
  const pageHeight = doc.internal.pageSize.getHeight()
  const contentWidth = pageWidth - PAGE_MARGIN * 2
  let y = PAGE_MARGIN

  function drawPageHeader() {
    doc.setTextColor(...ORANGE)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8)
    doc.text('CHIC KAMPUS  |  LAPORAN PENJUALAN', PAGE_MARGIN, 9)

    doc.setTextColor(...INK)
    doc.setFontSize(15)
    doc.text('Laporan Keuangan dan Penjualan', PAGE_MARGIN, 17)

    doc.setTextColor(...MUTED)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.text(`Periode: ${report.periodLabel}`, PAGE_MARGIN, 23)
    doc.text(`Dibuat: ${report.generatedAt}`, pageWidth - PAGE_MARGIN, 23, { align: 'right' })
    doc.setDrawColor(...LINE)
    doc.line(PAGE_MARGIN, 27, pageWidth - PAGE_MARGIN, 27)
    y = 33
  }

  function addPage() {
    doc.addPage()
    drawPageHeader()
  }

  function ensureSpace(height) {
    if (y + height > pageHeight - 14) addPage()
  }

  function sectionTitle(title) {
    ensureSpace(9)
    doc.setTextColor(...INK)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(10)
    doc.text(title, PAGE_MARGIN, y)
    y += 5
  }

  function drawMetricCards() {
    const metrics = [
      ['Omzet', currency(report.summary.revenue)],
      ['HPP estimasi', currency(report.summary.estimatedCogs)],
      ['Laba kotor estimasi', currency(report.summary.grossProfit)],
      ['Margin kotor', `${Number(report.summary.margin).toLocaleString('id-ID', { maximumFractionDigits: 1 })}%`],
      ['Transaksi lunas', number(report.summary.transactionCount)],
      ['Porsi terjual', number(report.summary.portionCount)],
      ['Rata-rata transaksi', currency(report.summary.averageTicket)],
      ['Rating pelanggan', report.summary.reviewCount
        ? `${Number(report.summary.averageRating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} / 5 (${number(report.summary.reviewCount)} ulasan)`
        : 'Belum ada ulasan'],
    ]
    const gap = 4
    const cardWidth = (contentWidth - gap * 3) / 4
    const cardHeight = 19
    metrics.forEach(([label, value], index) => {
      const row = Math.floor(index / 4)
      const column = index % 4
      const x = PAGE_MARGIN + column * (cardWidth + gap)
      const cardY = y + row * (cardHeight + 3)
      doc.setFillColor(...PALE)
      doc.setDrawColor(...LINE)
      doc.roundedRect(x, cardY, cardWidth, cardHeight, 2, 2, 'FD')
      doc.setTextColor(...MUTED)
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7)
      doc.text(label, x + 3, cardY + 6)
      doc.setTextColor(...INK)
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(9)
      doc.text(doc.splitTextToSize(value, cardWidth - 6)[0], x + 3, cardY + 14)
    })
    y += cardHeight * 2 + 8
  }

  function drawTrendChart(x, top, width, height, groupBy) {
    const rows = report.isSingleDay ? report.hourlyTrend : [...report.trend].reverse()
    const points = report.isSingleDay
      ? rows.map((row) => ({
        label: row.period_start.slice(11, 13),
        value: report.chartMetric === 'transactions' ? Number(row.transaction_count) : Number(row.revenue),
      }))
      : chartPoints(rows, groupBy)
    doc.setTextColor(...INK)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(9)
    doc.text(report.isSingleDay ? 'Tren per jam' : 'Tren penjualan', x, top)
    const chartTop = top + 8
    const chartBottom = chartTop + height - 19
    const chartHeight = chartBottom - chartTop
    const maxValue = Math.max(1, ...points.map((point) => point.value))
    const gap = points.length > 18 ? 1 : 2
    const barWidth = Math.max(1.2, (width - gap * Math.max(0, points.length - 1)) / Math.max(points.length, 1))

    doc.setDrawColor(...LINE)
    doc.line(x, chartBottom, x + width, chartBottom)
    points.forEach((point, index) => {
      const barHeight = point.value ? Math.max(0.7, (point.value / maxValue) * chartHeight) : 0
      const barX = x + index * (barWidth + gap)
      doc.setFillColor(...ORANGE)
      if (barHeight) doc.roundedRect(barX, chartBottom - barHeight, barWidth, barHeight, 0.6, 0.6, 'F')
      if (points.length <= 12 || index % Math.ceil(points.length / 8) === 0) {
        doc.setTextColor(...MUTED)
        doc.setFont('helvetica', 'normal')
        doc.setFontSize(5.5)
        const label = point.label.length > 12 ? point.label.slice(0, 11) : point.label
        doc.text(label, barX + barWidth / 2, chartBottom + 5, { align: 'center', maxWidth: Math.max(barWidth + gap, 14) })
      }
    })
    if (!points.length) {
      doc.setTextColor(...MUTED)
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8)
      doc.text('Tidak ada penjualan pada rentang ini.', x, chartTop + 12)
    }
  }

  function drawPaymentSummary(x, top, width) {
    doc.setDrawColor(...LINE)
    doc.setFillColor(250, 249, 247)
    doc.roundedRect(x, top, width, 64, 2, 2, 'FD')
    doc.setTextColor(...INK)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(9)
    doc.text('Metode pembayaran', x + 4, top + 7)
    const rows = [
      ['QRIS', report.summary.qrisRevenue],
      ['Tunai', report.summary.cashRevenue],
    ]
    rows.forEach(([label, value], index) => {
      const rowY = top + 18 + index * 19
      const amount = Number(value)
      const share = report.summary.revenue ? Math.round(amount / report.summary.revenue * 100) : 0
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(8)
      doc.setTextColor(...INK)
      doc.text(label, x + 4, rowY)
      doc.setFont('helvetica', 'normal')
      doc.text(currency(amount), x + width - 4, rowY, { align: 'right' })
      doc.setTextColor(...MUTED)
      doc.setFontSize(7)
      doc.text(`${share}% dari omzet`, x + 4, rowY + 5)
      doc.setFillColor(...LINE)
      doc.roundedRect(x + 4, rowY + 8, width - 8, 2, 1, 1, 'F')
      if (share) {
        doc.setFillColor(...ORANGE)
        doc.roundedRect(x + 4, rowY + 8, (width - 8) * share / 100, 2, 1, 1, 'F')
      }
    })
  }

  function drawTopProducts() {
    const rows = report.products.slice(0, 6)
    sectionTitle('Menu terlaris')
    const x = PAGE_MARGIN
    const labelWidth = 205
    const qtyWidth = 28
    const headerHeight = 7
    const rowHeight = 6
    ensureSpace(headerHeight + Math.max(rows.length, 1) * rowHeight)
    doc.setFillColor(...PALE)
    doc.rect(x, y - 4.5, contentWidth, headerHeight, 'F')
    doc.setTextColor(...MUTED)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(7)
    doc.text('Menu', x + 2, y)
    doc.text('Porsi', x + labelWidth + qtyWidth - 2, y, { align: 'right' })
    doc.text('Omzet', x + contentWidth - 2, y, { align: 'right' })
    y += rowHeight
    if (!rows.length) {
      doc.setFont('helvetica', 'normal')
      doc.setTextColor(...MUTED)
      doc.text('Belum ada penjualan lunas.', x + 2, y)
      y += rowHeight
      return
    }
    rows.forEach((row) => {
      ensureSpace(rowHeight)
      doc.setFont('helvetica', 'normal')
      doc.setTextColor(...INK)
      doc.setFontSize(7)
      doc.text(row.label, x + 2, y, { maxWidth: labelWidth - 5 })
      doc.text(number(row.total_qty), x + labelWidth + qtyWidth - 2, y, { align: 'right' })
      doc.text(currency(row.total_sales), x + contentWidth - 2, y, { align: 'right' })
      y += rowHeight
    })
  }

  function drawDetailTable() {
    addPage()
    const transactionDetail = report.isSingleDay && report.detailMode === 'transaction'
    sectionTitle(transactionDetail ? 'Rekap per transaksi' : report.isSingleDay ? 'Rekap per jam' : 'Rekap per periode')
    const periodColumns = [
      { title: 'Periode', width: 49, align: 'left' },
      { title: 'Transaksi', width: 18, align: 'right' },
      { title: 'Porsi', width: 15, align: 'right' },
      { title: 'Omzet', width: 31, align: 'right' },
      { title: 'HPP', width: 28, align: 'right' },
      { title: 'Laba kotor', width: 32, align: 'right' },
      { title: 'QRIS', width: 26, align: 'right' },
      { title: 'Tunai', width: 26, align: 'right' },
      { title: 'Ulasan', width: 16, align: 'right' },
      { title: 'Rating', width: 18, align: 'right' },
    ]
    const transactionColumns = [
      { title: 'Waktu', width: 23, align: 'left' },
      { title: 'Antrean', width: 22, align: 'right' },
      { title: 'Metode', width: 25, align: 'left' },
      { title: 'Porsi', width: 16, align: 'right' },
      { title: 'Omzet', width: 34, align: 'right' },
      { title: 'HPP', width: 31, align: 'right' },
      { title: 'Laba kotor', width: 36, align: 'right' },
      { title: 'Rating', width: 17, align: 'right' },
    ]
    const columns = transactionDetail ? transactionColumns : periodColumns
    const tableWidth = columns.reduce((sum, column) => sum + column.width, 0)
    const tableX = PAGE_MARGIN + (contentWidth - tableWidth) / 2
    const detailRows = transactionDetail
      ? report.transactions
      : report.isSingleDay
        ? report.hourlyTrend
        : report.trend

    function drawTableHeader() {
      const height = 8
      doc.setFillColor(...INK)
      doc.rect(tableX, y - 4, tableWidth, height, 'F')
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(6.5)
      doc.setTextColor(255, 255, 255)
      let x = tableX
      columns.forEach((column) => {
        const textX = column.align === 'right' ? x + column.width - 1.5 : x + 1.5
        doc.text(column.title, textX, y + 1, { align: column.align, maxWidth: column.width - 3 })
        x += column.width
      })
      y += height
    }

    drawTableHeader()
    doc.setTextColor(...MUTED)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(6.5)
    doc.text('Hanya transaksi lunas. Laba kotor = omzet - HPP estimasi; belum dikurangi biaya operasional.', tableX, y + 1)
    y += 7

    if (!detailRows.length) {
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8)
      doc.setTextColor(...MUTED)
      doc.text('Tidak ada transaksi lunas pada rentang ini.', tableX, y + 5)
      return
    }

    detailRows.forEach((row, index) => {
      const values = transactionDetail
        ? [
          chartTime(row.created_at),
          `#${number(row.queue_number)}`,
          row.payment_method === 'qris' ? 'QRIS' : 'Tunai',
          number(row.portion_count),
          currency(row.revenue),
          currency(row.estimated_cogs),
          currency(Number(row.revenue) - Number(row.estimated_cogs)),
          String(row.review_rating ?? '-'),
        ]
        : [
          report.isSingleDay
            ? `${row.period_start.slice(11, 13)}.00-${String(Number(row.period_start.slice(11, 13)) + 1).padStart(2, '0')}.00`
            : periodLabel(row.period_start, report.groupBy),
          number(row.transaction_count),
          number(row.portion_count),
          currency(row.revenue),
          currency(row.estimated_cogs),
          currency(Number(row.revenue) - Number(row.estimated_cogs)),
          currency(row.qris_revenue),
          currency(row.cash_revenue),
          number(row.review_count),
          Number(row.review_count)
            ? Number(row.average_rating).toLocaleString('id-ID', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
            : '-',
        ]
      const rowHeight = 7
      if (y + rowHeight > pageHeight - 14) {
        addPage()
        sectionTitle(transactionDetail ? 'Rekap per transaksi - lanjutan' : report.isSingleDay ? 'Rekap per jam - lanjutan' : 'Rekap per periode - lanjutan')
        drawTableHeader()
      }
      if (index % 2 === 0) {
        doc.setFillColor(250, 249, 247)
        doc.rect(tableX, y - 4, tableWidth, rowHeight, 'F')
      }
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(6.5)
      doc.setTextColor(...INK)
      let x = tableX
      values.forEach((value, valueIndex) => {
        const column = columns[valueIndex]
        const textX = column.align === 'right' ? x + column.width - 1.5 : x + 1.5
        doc.text(value, textX, y, { align: column.align, maxWidth: column.width - 3 })
        x += column.width
      })
      y += rowHeight
    })
  }

  drawPageHeader()
  drawMetricCards()
  const chartWidth = contentWidth - 96
  drawTrendChart(PAGE_MARGIN, y, chartWidth, 55, report.groupBy)
  drawPaymentSummary(PAGE_MARGIN + chartWidth + 8, y - 1, contentWidth - chartWidth - 8)
  y += 68
  drawTopProducts()
  drawDetailTable()

  const pageCount = doc.internal.getNumberOfPages()
  for (let page = 1; page <= pageCount; page += 1) {
    doc.setPage(page)
    doc.setDrawColor(...LINE)
    doc.line(PAGE_MARGIN, pageHeight - 9, pageWidth - PAGE_MARGIN, pageHeight - 9)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(7)
    doc.setTextColor(...MUTED)
    doc.text('Chic Kampus - Dokumen laporan penjualan', PAGE_MARGIN, pageHeight - 5)
    doc.text(`Halaman ${page} dari ${pageCount}`, pageWidth - PAGE_MARGIN, pageHeight - 5, { align: 'right' })
  }

  return doc
}

export function downloadFinancialReportPdf(report) {
  const document = createFinancialReportPdf(report)
  document.save(`laporan-keuangan-chic-kampus-${report.startDate}-${report.endDate}.pdf`)
}
