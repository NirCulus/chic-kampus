<script setup>
import { getCarb, getSauce, getSize } from '../../constants/menu'

defineProps({ order: { type: Object, required: true } })
const money = (value) => `Rp${Number(value).toLocaleString('id-ID')}`
const date = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
</script>

<template>
  <article id="thermal-receipt" class="receipt-hidden"><header class="text-center"><b>CHIC KAMPUS</b><br><span>Chicken Steak · UNSIKA</span><hr><strong>ANTREAN #{{ order.queue_number }}</strong></header><p>{{ date(order.created_at) }}</p><p>Pembayaran: {{ order.payment_method === 'qris' ? 'QRIS' : 'TUNAI' }} · {{ order.payment_status === 'paid' ? 'LUNAS' : 'MENUNGGU' }}</p><hr><div v-for="item in order.items" :key="item.key" class="mb-1 flex justify-between"><span>{{ item.qty }}x {{ getSize(item.size)?.label }}<br>{{ getSauce(item.sauceVariant)?.label }} · {{ getCarb(item.carbType)?.label }}</span><b>{{ money(item.subtotal) }}</b></div><hr><div class="flex justify-between font-bold"><span>TOTAL</span><span>{{ money(order.total_revenue) }}</span></div><hr><p class="text-center">Terima kasih. Simpan nomor antrean Anda.</p></article>
</template>