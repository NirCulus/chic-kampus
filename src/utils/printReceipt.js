const RECEIPT_ID = 'thermal-receipt'
const PAGE_STYLE_ID = 'receipt-page-size'

function cleanupReceiptPrint(receipt, pageStyle, onAfterPrint) {
  window.removeEventListener('afterprint', onAfterPrint)
  receipt.classList.remove('receipt-printing')
  pageStyle.remove()
}

export async function printReceipt() {
  const receipt = document.getElementById(RECEIPT_ID)
  if (!receipt) throw new Error('Struk tidak tersedia untuk dicetak.')

  const oldPageStyle = document.getElementById(PAGE_STYLE_ID)
  oldPageStyle?.remove()
  receipt.classList.add('receipt-printing')
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))

  const { width, height } = receipt.getBoundingClientRect()
  if (width <= 0 || height <= 0) {
    receipt.classList.remove('receipt-printing')
    throw new Error('Ukuran struk tidak dapat ditentukan.')
  }

  const pixelsToMillimeters = 25.4 / 96
  const pageWidth = Math.ceil(width * pixelsToMillimeters * 10) / 10
  const pageHeight = Math.ceil(height * pixelsToMillimeters * 10) / 10
  const pageStyle = document.createElement('style')
  pageStyle.id = PAGE_STYLE_ID
  pageStyle.textContent = `@page { size: ${pageWidth}mm ${pageHeight}mm; margin: 0; }`
  document.head.append(pageStyle)

  const onAfterPrint = () => cleanupReceiptPrint(receipt, pageStyle, onAfterPrint)
  window.addEventListener('afterprint', onAfterPrint, { once: true })
  window.print()
}
