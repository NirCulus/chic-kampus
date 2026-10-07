import { computed, ref } from 'vue'
import { getCarb, getSauce, getSize } from '../constants/menu'

const cart = ref([])

function assertConfiguration({ size, sauceVariant, carbType, qty = 1 }) {
  if (!getSize(size) || !getSauce(sauceVariant) || !getCarb(carbType)) throw new Error('Konfigurasi menu tidak valid.')
  if (!Number.isInteger(qty) || qty < 1) throw new Error('Jumlah pesanan harus minimal satu.')
}

export function useCart() {
  const totalItems = computed(() => cart.value.reduce((total, item) => total + item.qty, 0))
  const totalPrice = computed(() => cart.value.reduce((total, item) => total + item.subtotal, 0))
  const isEmpty = computed(() => cart.value.length === 0)

  function addItem(configuration) {
    assertConfiguration(configuration)
    const size = getSize(configuration.size)
    const key = `${configuration.size}:${configuration.sauceVariant}:${configuration.carbType}`
    const existing = cart.value.find((item) => item.key === key)
    if (existing) {
      existing.qty += configuration.qty ?? 1
      existing.subtotal = existing.qty * existing.unitPrice
      return
    }
    const qty = configuration.qty ?? 1
    cart.value.push({ key, size: configuration.size, sauceVariant: configuration.sauceVariant, carbType: configuration.carbType, qty, unitPrice: size.price, subtotal: size.price * qty })
  }

  function updateQuantity(key, qty) {
    if (!Number.isInteger(qty) || qty < 1) return removeItem(key)
    const item = cart.value.find((line) => line.key === key)
    if (!item) return
    item.qty = qty
    item.subtotal = item.unitPrice * qty
  }

  function removeItem(key) { cart.value = cart.value.filter((item) => item.key !== key) }
  function clearCart() { cart.value = [] }
  function toOrderItems() {
    return cart.value.map(({ size, sauceVariant, carbType, qty }) => ({ size, sauce_variant: sauceVariant, carb_type: carbType, qty }))
  }

  return { cart, totalItems, totalPrice, isEmpty, addItem, updateQuantity, removeItem, clearCart, toOrderItems }
}
