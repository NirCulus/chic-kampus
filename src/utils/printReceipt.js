import { getCarb, getSauce, getSize } from '../constants/menu.js'

const MAX_PAGE_WIDTH_MM = 58
const HORIZONTAL_PADDING_MM = 2.5
const MAX_CONTENT_WIDTH_MM = MAX_PAGE_WIDTH_MM - HORIZONTAL_PADDING_MM * 2
const FONT_SIZE_PT = 9
const LINE_HEIGHT_MM = 4.2

const money = (value) => `Rp${Number(value).toLocaleString('id-ID')}`
const receiptDate = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
const safeText = (value) => String(value).replace(/[·•]/g, '-')

function createDocument(JsPDF) {
  const document = new JsPDF({ orientation: 'portrait', unit: 'mm', format: [MAX_PAGE_WIDTH_MM, 100], compress: true })
  document.setFont('courier', 'normal')
  document.setFontSize(FONT_SIZE_PT)
  return document
}

function textWidth(document, text, bold = false) {
  document.setFont('courier', bold ? 'bold' : 'normal')
  return document.getTextWidth(safeText(text))
}

function wrappedLines(document, text, width) {
  return document.splitTextToSize(safeText(text), width)
}

function buildOperations(document, order, contentWidth) {
  const operations = []
  const addText = (text, bold = false) => operations.push({ type: 'text', text, bold })
  const addRule = () => operations.push({ type: 'rule' })
  const addGap = () => operations.push({ type: 'gap' })
  const addWrapped = (text, bold = false, width = contentWidth) => {
    for (const line of wrappedLines(document, text, width)) addText(line, bold)
  }
  const addAmountRow = (label, amount, bold = false) => {
    const amountWidth = textWidth(document, amount, bold)
    const labelWidth = Math.max(8, contentWidth - amountWidth - 2)
    const labelLines = wrappedLines(document, label, labelWidth)
    operations.push({ type: 'row', left: labelLines[0], right: amount, bold })
    for (const line of labelLines.slice(1)) addText(line, bold)
  }

  addText('CHIC KAMPUS', true)
  addText('Chicken Steak - UNSIKA')
  addGap()
  addText(`ANTREAN #${order.queue_number}`, true)
  addRule()
  addWrapped(receiptDate(order.created_at))
  addWrapped(`Pembayaran: ${order.payment_method === 'qris' ? 'QRIS' : 'TUNAI'} - ${order.payment_status === 'paid' ? 'LUNAS' : 'MENUNGGU'}`)
  addRule()

  for (const item of order.items) {
    const title = `${item.qty}x ${getSize(item.size)?.label ?? item.size}`
    const amount = money(item.subtotal)
    addAmountRow(title, amount)
    addWrapped(`${getSauce(item.sauceVariant)?.label ?? item.sauceVariant} - ${getCarb(item.carbType)?.label ?? item.carbType}`)
    addGap()
  }

  addRule()
  addAmountRow('TOTAL', money(order.total_revenue), true)
  addRule()
  addWrapped('Terima kasih. Simpan nomor antrean Anda.')
  return operations
}

export async function createReceiptPdf(order) {
  if (!order || !Number.isInteger(Number(order.queue_number)) || !Array.isArray(order.items) || order.items.length === 0) {
    throw new Error('Data pesanan tidak valid untuk membuat struk.')
  }

  const { jsPDF } = await import('jspdf')
  const document = createDocument(jsPDF)
  const paymentMethod = order.payment_method === 'qris' ? 'QRIS' : 'TUNAI'
  const paymentStatus = order.payment_status === 'paid' ? 'LUNAS' : 'MENUNGGU'
  const paymentLine = `Pembayaran: ${paymentMethod} - ${paymentStatus}`
  const measuredLines = [
    'CHIC KAMPUS',
    'Chicken Steak - UNSIKA',
    `ANTREAN #${order.queue_number}`,
    ...wrappedLines(document, receiptDate(order.created_at), MAX_CONTENT_WIDTH_MM),
    ...wrappedLines(document, paymentLine, MAX_CONTENT_WIDTH_MM),
    ...order.items.flatMap((item) => {
      const description = `${getSauce(item.sauceVariant)?.label ?? item.sauceVariant} - ${getCarb(item.carbType)?.label ?? item.carbType}`
      return wrappedLines(document, description, MAX_CONTENT_WIDTH_MM)
    }),
    ...wrappedLines(document, 'Terima kasih. Simpan nomor antrean Anda.', MAX_CONTENT_WIDTH_MM),
  ]
  const longestTextWidth = Math.max(
    ...measuredLines.map((line) => textWidth(document, line)),
  )
  const amountRowWidth = Math.max(
    ...order.items.map((item) => textWidth(document, `${item.qty}x ${getSize(item.size)?.label ?? item.size}`) + textWidth(document, money(item.subtotal)) + 2),
    textWidth(document, 'TOTAL', true) + textWidth(document, money(order.total_revenue), true) + 2,
  )
  const contentWidth = Math.min(MAX_CONTENT_WIDTH_MM, Math.max(longestTextWidth, amountRowWidth))
  const operations = buildOperations(document, order, contentWidth)
  const contentHeight = operations.reduce((height, operation) => height + (operation.type === 'gap' ? 1.5 : operation.type === 'rule' ? 3.2 : LINE_HEIGHT_MM), 0)
  const pageHeight = Math.ceil((contentHeight + HORIZONTAL_PADDING_MM * 2 + 2.8 + 2.5) * 10) / 10
  const pageWidth = Math.ceil((contentWidth + HORIZONTAL_PADDING_MM * 2) * 10) / 10
  document.deletePage(1)
  document.addPage([pageWidth, pageHeight], 'portrait')
  document.setFontSize(FONT_SIZE_PT)

  let y = HORIZONTAL_PADDING_MM + 2.8
  for (const operation of operations) {
    if (operation.type === 'gap') {
      y += 1.5
      continue
    }
    if (operation.type === 'rule') {
      y += 1
      document.setLineWidth(0.15)
      document.line(HORIZONTAL_PADDING_MM, y, pageWidth - HORIZONTAL_PADDING_MM, y)
      y += 2.2
      continue
    }

    document.setFont('courier', operation.bold ? 'bold' : 'normal')
    if (operation.type === 'row') {
      document.text(safeText(operation.left), HORIZONTAL_PADDING_MM, y)
      document.text(safeText(operation.right), pageWidth - HORIZONTAL_PADDING_MM, y, { align: 'right' })
    } else {
      document.text(safeText(operation.text), HORIZONTAL_PADDING_MM, y)
    }
    y += LINE_HEIGHT_MM
  }

  return document
}

export async function downloadReceiptPdf(order) {
  const document = await createReceiptPdf(order)
  document.save(`chic-kampus-antrean-${order.queue_number}.pdf`)
}
