import { ref } from 'vue'
import { requireSupabase } from '../supabase'

const orders = ref([])
const loading = ref(false)
const error = ref(null)

export function useOrders() {
  async function fetchOrders({ activeOnly = false } = {}) {
    loading.value = true
    error.value = null
    let query = requireSupabase().from('orders').select('*, order_items(*)').order('created_at', { ascending: false })
    if (activeOnly) query = query.neq('status', 'completed').neq('status', 'cancelled')
    const { data, error: requestError } = await query
    loading.value = false
    if (requestError) { error.value = requestError; throw requestError }
    orders.value = data ?? []
    return orders.value
  }

  async function createOrder(paymentMethod, items) {
    if (!['qris', 'cash'].includes(paymentMethod)) throw new Error('Metode pembayaran tidak valid.')
    if (!items?.length) throw new Error('Keranjang pesanan masih kosong.')
    loading.value = true
    error.value = null
    const { data, error: requestError } = await requireSupabase().rpc('create_order', { p_payment_method: paymentMethod, p_items: items })
    loading.value = false
    if (requestError) { error.value = requestError; throw requestError }
    return data?.[0] ?? data
  }

  async function confirmCashPayment(orderId) {
    const { data, error: requestError } = await requireSupabase().rpc('confirm_cash_payment', { p_order_id: orderId })
    if (requestError) throw requestError
    return data
  }

  async function updateOrderStatus(orderId, status) {
    if (!['processing', 'completed'].includes(status)) throw new Error('Status pesanan tidak valid.')
    const { data, error: requestError } = await requireSupabase().rpc('update_order_status', { p_order_id: orderId, p_status: status })
    if (requestError) throw requestError
    return data
  }

  async function cancelOrder(orderId, notes) {
    const { data, error: requestError } = await requireSupabase().rpc('cancel_order', { p_order_id: orderId, p_notes: notes || 'Pesanan dibatalkan oleh owner.' })
    if (requestError) throw requestError
    return data
  }

  return { orders, loading, error, fetchOrders, createOrder, confirmCashPayment, updateOrderStatus, cancelOrder }
}
