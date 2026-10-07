<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { getCarb, getSauce, getSize } from '../../constants/menu'
import { useOrders } from '../../composables/useOrders'
import { requireSupabase } from '../../supabase'
import ThermalReceipt from '../kiosk/ThermalReceipt.vue'

const { orders, loading, error, fetchOrders, confirmCashPayment, updateOrderStatus } = useOrders()
const actionOrderId = ref(null)
const actionError = ref('')
const receiptOrder = ref(null)
let ordersChannel = null

const activeOrders = computed(() => [...orders.value].sort((a, b) => a.queue_number - b.queue_number))
const money = (value) => `Rp${Number(value).toLocaleString('id-ID')}`
const date = (value) => new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit' }).format(new Date(value))

function normalizeOrder(order) {
  return {
    ...order,
    items: (order.order_items ?? []).map((item) => ({
      key: item.id,
      size: item.size,
      sauceVariant: item.sauce_variant,
      carbType: item.carb_type,
      qty: item.qty,
      subtotal: item.subtotal,
    })),
  }
}

function statusMeta(order) {
  if (order.status === 'waiting') return { label: 'Menunggu tunai', className: 'bg-amber-100 text-amber-800' }
  if (order.status === 'processing') return { label: 'Sedang diproses', className: 'bg-blue-100 text-blue-800' }
  if (order.status === 'completed') return { label: 'Selesai', className: 'bg-emerald-100 text-emerald-800' }
  return { label: 'Dibatalkan', className: 'bg-stone-200 text-stone-700' }
}

function itemDescription(item) {
  return `${getSize(item.size)?.label ?? item.size} · ${getSauce(item.sauce_variant)?.label ?? item.sauce_variant} · ${getCarb(item.carb_type)?.label ?? item.carb_type}`
}

async function refresh() {
  try {
    await fetchOrders({ activeOnly: true })
  } catch (requestError) {
    actionError.value = requestError.message || 'Antrean belum dapat dimuat.'
  }
}

async function receiveCash(order) {
  if (actionOrderId.value) return
  actionOrderId.value = order.id
  actionError.value = ''
  try {
    const updatedOrder = await confirmCashPayment(order.id)
    receiptOrder.value = normalizeOrder({ ...order, ...updatedOrder, payment_status: 'paid', status: 'processing' })
    await refresh()
    await nextTick()
    window.print()
  } catch (requestError) {
    actionError.value = requestError.message || 'Pembayaran tunai belum dapat dikonfirmasi.'
  } finally {
    actionOrderId.value = null
  }
}

async function completeOrder(order) {
  if (actionOrderId.value) return
  actionOrderId.value = order.id
  actionError.value = ''
  try {
    await updateOrderStatus(order.id, 'completed')
    await refresh()
  } catch (requestError) {
    actionError.value = requestError.message || 'Status pesanan belum dapat diperbarui.'
  } finally {
    actionOrderId.value = null
  }
}

onMounted(async () => {
  await refresh()
  ordersChannel = requireSupabase()
    .channel('owner-active-orders')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, refresh)
    .subscribe()
})

onBeforeUnmount(() => {
  if (ordersChannel) requireSupabase().removeChannel(ordersChannel)
})
</script>

<template>
  <section>
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Operasional</p>
        <h2 class="mt-1 text-xl font-black">Antrean pesanan</h2>
        <p class="mt-1 text-sm text-stone-500">Diperbarui otomatis saat pesanan masuk atau status berubah.</p>
      </div>
      <button class="rounded-xl border border-orange-200 bg-white px-4 py-2 text-sm font-bold text-chic-orange disabled:opacity-60" :disabled="loading" type="button" @click="refresh">
        {{ loading ? 'Memuat…' : 'Muat ulang' }}
      </button>
    </div>

    <p v-if="actionError || error" class="mt-4 rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">{{ actionError || error?.message }}</p>

    <div v-if="loading && !activeOrders.length" class="mt-5 rounded-2xl border border-orange-100 bg-white p-7 text-center text-sm text-stone-500">Memuat antrean…</div>
    <div v-else-if="!activeOrders.length" class="mt-5 rounded-2xl border border-dashed border-orange-200 bg-white p-8 text-center">
      <p class="font-bold">Belum ada pesanan aktif.</p>
      <p class="mt-1 text-sm text-stone-500">Pesanan baru dari Kiosk akan muncul di sini.</p>
    </div>

    <div v-else class="mt-5 grid gap-4 xl:grid-cols-2">
      <article v-for="order in activeOrders" :key="order.id" class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
        <div class="flex items-start gap-3">
          <div class="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-orange-50 text-xl font-black text-chic-orange">#{{ order.queue_number }}</div>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="font-black">Pesanan #{{ order.queue_number }}</h3>
              <span class="rounded-full px-2.5 py-1 text-xs font-bold" :class="statusMeta(order).className">{{ statusMeta(order).label }}</span>
            </div>
            <p class="mt-1 text-xs text-stone-500">{{ date(order.created_at) }} · {{ order.payment_method === 'qris' ? 'QRIS' : 'Tunai' }}</p>
          </div>
          <strong class="text-sm">{{ money(order.total_revenue) }}</strong>
        </div>

        <ul class="mt-4 divide-y divide-stone-100 border-y border-stone-100">
          <li v-for="item in order.order_items" :key="item.id" class="flex gap-3 py-3 text-sm">
            <b>{{ item.qty }}×</b>
            <span class="flex-1">{{ itemDescription(item) }}</span>
            <span>{{ money(item.subtotal) }}</span>
          </li>
        </ul>

        <div class="mt-4 flex flex-wrap gap-2">
          <button
            v-if="order.payment_method === 'cash' && order.payment_status === 'waiting'"
            class="rounded-xl bg-chic-orange px-4 py-2.5 text-sm font-bold text-white disabled:bg-stone-300"
            :disabled="Boolean(actionOrderId)"
            type="button"
            @click="receiveCash(order)"
          >
            {{ actionOrderId === order.id ? 'Memproses…' : 'Tunai diterima & cetak struk' }}
          </button>
          <button
            v-if="order.status === 'processing'"
            class="rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white disabled:bg-stone-300"
            :disabled="Boolean(actionOrderId)"
            type="button"
            @click="completeOrder(order)"
          >
            {{ actionOrderId === order.id ? 'Memproses…' : 'Tandai selesai' }}
          </button>
          <span v-if="order.payment_method === 'qris' && order.status === 'processing'" class="self-center text-xs font-medium text-stone-500">QRIS telah lunas · struk sudah dicetak di Kiosk</span>
        </div>
      </article>
    </div>

    <ThermalReceipt v-if="receiptOrder" :order="receiptOrder" />
  </section>
</template>