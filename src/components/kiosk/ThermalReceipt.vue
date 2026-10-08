<script setup>
import { getCarb, getSauce, getSize } from '../../constants/menu'

defineProps({ order: { type: Object, required: true } })
const money = (value) => `Rp${Number(value).toLocaleString('id-ID')}`
const date = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
</script>

<template>
  <Teleport to="body">
    <article id="thermal-receipt" class="receipt-hidden">
      <header class="receipt-header">
        <strong>CHIC KAMPUS</strong>
        <span>Chicken Steak · UNSIKA</span>
        <hr>
        <b>ANTREAN #{{ order.queue_number }}</b>
      </header>
      <p>{{ date(order.created_at) }}</p>
      <p>Pembayaran: {{ order.payment_method === 'qris' ? 'QRIS' : 'TUNAI' }} · {{ order.payment_status === 'paid' ? 'LUNAS' : 'MENUNGGU' }}</p>
      <hr>
      <div v-for="item in order.items" :key="item.key" class="receipt-item">
        <span>{{ item.qty }}x {{ getSize(item.size)?.label }}<br>{{ getSauce(item.sauceVariant)?.label }} · {{ getCarb(item.carbType)?.label }}</span>
        <b>{{ money(item.subtotal) }}</b>
      </div>
      <hr>
      <div class="receipt-total"><b>TOTAL</b><b>{{ money(order.total_revenue) }}</b></div>
      <hr>
      <p class="receipt-footer">Terima kasih. Simpan nomor antrean Anda.</p>
    </article>
  </Teleport>
</template>