<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue'
import CartSidebar from '../components/kiosk/CartSidebar.vue'
import CheckoutModal from '../components/kiosk/CheckoutModal.vue'
import MenuGrid from '../components/kiosk/MenuGrid.vue'
import OfflineIndicator from '../components/kiosk/OfflineIndicator.vue'
import logo from '../assets/logo-chic-kampus.jpg'
import { CARBS, getSize, SAUCES } from '../constants/menu'
import { useCart } from '../composables/useCart'
import { useIdleTimer } from '../composables/useIdleTimer'
import { useInventory } from '../composables/useInventory'
import { useOrders } from '../composables/useOrders'
import { requireSupabase } from '../supabase'
import { downloadReceiptPdf } from '../utils/printReceipt'

const { cart, totalPrice, isEmpty, addItem, updateQuantity, removeItem, clearCart, toOrderItems } = useCart()
const { ingredients, fetchIngredients, isItemAvailable, isCartAvailable } = useInventory()
const { createOrder, loading: orderLoading } = useOrders()
const selectedSize = ref(null)
const selectedSauce = ref(null)
const selectedCarb = ref(null)
const checkoutOpen = ref(false)
const receiptOrder = ref(null)
const receiptError = ref('')
const reviewRating = ref(0)
const reviewName = ref('')
const reviewComment = ref('')
const reviewSubmitting = ref(false)
const reviewError = ref('')
const reviewSubmitted = ref(false)
const isOnline = ref(navigator.onLine)
const notice = ref('')
const money = (value) => `Rp${value.toLocaleString('id-ID')}`

const customizationOpen = computed(() => Boolean(selectedSize.value))
const selectedConfiguration = computed(() => selectedSize.value && selectedSauce.value && selectedCarb.value ? { size: selectedSize.value, sauceVariant: selectedSauce.value, carbType: selectedCarb.value } : null)
const canAddSelected = computed(() => selectedConfiguration.value && isItemAvailable(selectedConfiguration.value))
const checkoutDisabled = computed(() => isEmpty.value || !isOnline.value || !isCartAvailable(cart.value) || orderLoading.value)

function chooseSize(size) {
  selectedSize.value = size
  selectedSauce.value = null
  selectedCarb.value = null
  notice.value = ''
}
function closeCustomization() {
  selectedSize.value = null
  selectedSauce.value = null
  selectedCarb.value = null
  notice.value = ''
}
function addSelectedItem() {
  if (!selectedConfiguration.value) { notice.value = 'Pilih saus dan karbohidrat terlebih dahulu.'; return }
  if (!canAddSelected.value) { notice.value = 'Bahan untuk pilihan ini sedang tidak mencukupi.'; return }
  addItem(selectedConfiguration.value)
  closeCustomization()
}
function closeEverything() { clearCart(); closeCustomization(); checkoutOpen.value = false; receiptOrder.value = null; receiptError.value = ''; notice.value = '' }
const idleTimer = useIdleTimer(closeEverything, 120_000)

async function submitOrder(method) {
  if (checkoutDisabled.value) return
  const receiptItems = cart.value.map((item) => ({ ...item }))
  try {
    const result = await createOrder(method, toOrderItems())
    receiptOrder.value = { ...result, items: receiptItems, created_at: new Date().toISOString(), payment_method: method }
    receiptError.value = ''
    reviewRating.value = 0
    reviewName.value = ''
    reviewComment.value = ''
    reviewError.value = ''
    reviewSubmitted.value = false
    checkoutOpen.value = false
    clearCart()
    closeCustomization()
    if (method === 'qris') {
      await nextTick()
      await retryReceiptDownload()
    }
  } catch (error) { notice.value = error.message || 'Pesanan gagal dikirim. Silakan coba lagi.' }
}
async function submitReview() {
  if (!receiptOrder.value?.order_id || !reviewRating.value || reviewSubmitting.value || reviewSubmitted.value) return
  reviewSubmitting.value = true
  reviewError.value = ''
  try {
    const { error } = await requireSupabase().rpc('submit_review', {
      p_order_id: receiptOrder.value.order_id,
      p_customer_name: reviewName.value,
      p_rating: reviewRating.value,
      p_comment: reviewComment.value,
    })
    if (error) throw error
    reviewSubmitted.value = true
  } catch (error) {
    reviewError.value = error.message || 'Ulasan belum dapat dikirim.'
  } finally {
    reviewSubmitting.value = false
  }
}
async function retryReceiptDownload() {
  try {
    await downloadReceiptPdf(receiptOrder.value)
    receiptError.value = ''
  } catch (downloadError) {
    receiptError.value = downloadError.message || 'Silakan coba unduh ulang struk.'
  }
}
function setOnlineStatus() { isOnline.value = navigator.onLine }
onMounted(async () => {
  window.addEventListener('online', setOnlineStatus)
  window.addEventListener('offline', setOnlineStatus)
  idleTimer.start()
  try { await fetchIngredients() } catch (error) { notice.value = error.message || 'Stok belum dapat dimuat. Periksa koneksi internet.' }
})
onUnmounted(() => { window.removeEventListener('online', setOnlineStatus); window.removeEventListener('offline', setOnlineStatus) })
</script>

<template>
  <main class="min-h-screen bg-chic-cream text-chic-ink">
    <OfflineIndicator v-if="!isOnline" />
    <header class="border-b border-orange-100 bg-white"><div class="mx-auto flex max-w-7xl items-center gap-3 px-5 py-4"><img :src="logo" alt="Logo Chic Kampus" class="h-11 w-11 rounded-full object-cover"><div><p class="font-black tracking-tight">CHIC KAMPUS</p><p class="text-xs text-stone-500">Self-service ordering</p></div><RouterLink class="ml-auto rounded-full bg-orange-50 px-3 py-2 text-xs font-bold text-chic-orange" to="/reviews">★ Ulasan pelanggan</RouterLink></div></header>
    <div class="mx-auto grid max-w-7xl gap-6 px-5 py-7 lg:grid-cols-[1fr_360px]">
      <div><MenuGrid :ingredients="ingredients" @select="chooseSize" /><p v-if="notice && !customizationOpen" class="mt-5 rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">{{ notice }}</p></div>
      <CartSidebar :items="cart" :total="totalPrice" :disabled="checkoutDisabled" @change-quantity="updateQuantity" @remove="removeItem" @checkout="checkoutOpen = true" />
    </div>
    <div v-if="customizationOpen" class="screen-only fixed inset-0 z-40 grid place-items-center bg-black/50 p-4" @click.self="closeCustomization">
      <section class="w-full max-w-lg rounded-3xl bg-white p-6 shadow-2xl" role="dialog" aria-modal="true" aria-label="Sesuaikan pesanan">
        <div class="flex items-start justify-between gap-4"><div><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Sesuaikan pesanan</p><h2 class="mt-1 text-xl font-black">{{ getSize(selectedSize)?.label }}</h2><p class="mt-1 font-bold text-chic-orange">{{ money(getSize(selectedSize)?.price) }}</p></div><button class="grid h-9 w-9 place-items-center rounded-full bg-stone-100 text-lg font-bold" type="button" aria-label="Tutup" @click="closeCustomization">×</button></div>
        <fieldset class="mt-6"><legend class="text-sm font-bold">Pilih saus <span class="text-red-600">*</span></legend><div class="mt-3 grid gap-2 sm:grid-cols-2"><button v-for="sauce in SAUCES" :key="sauce.id" class="rounded-xl border px-4 py-3 text-left text-sm font-bold" :class="selectedSauce === sauce.id ? 'border-chic-orange bg-orange-50 text-chic-orange' : 'border-stone-200 text-stone-700'" type="button" @click="selectedSauce = sauce.id">{{ sauce.label }}</button></div></fieldset>
        <fieldset class="mt-5"><legend class="text-sm font-bold">Pilih karbohidrat <span class="text-red-600">*</span></legend><div class="mt-3 grid grid-cols-2 gap-2"><button v-for="carb in CARBS" :key="carb.id" class="rounded-xl border px-4 py-3 text-sm font-bold" :class="selectedCarb === carb.id ? 'border-chic-orange bg-orange-50 text-chic-orange' : 'border-stone-200 text-stone-700'" type="button" @click="selectedCarb = carb.id">{{ carb.label }}</button></div></fieldset>
        <p v-if="notice" class="mt-4 rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">{{ notice }}</p>
        <button class="mt-6 w-full rounded-xl bg-chic-orange px-5 py-3 font-bold text-white disabled:cursor-not-allowed disabled:bg-stone-300" :disabled="!canAddSelected" type="button" @click="addSelectedItem">{{ selectedConfiguration ? 'Tambah ke pesanan' : 'Pilih saus dan karbohidrat' }}</button>
      </section>
    </div>
    <CheckoutModal v-if="checkoutOpen" :total="totalPrice" :submitting="orderLoading" @close="checkoutOpen = false" @confirm="submitOrder" />
    <div v-if="receiptOrder" class="screen-only fixed inset-0 z-40 grid place-items-center overflow-y-auto bg-black/50 p-4"><section class="my-auto w-full max-w-lg rounded-3xl bg-white p-6 shadow-2xl sm:p-7" role="dialog" aria-modal="true" aria-labelledby="order-success-title"><div class="text-center"><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Pesanan berhasil</p><p class="mt-2 text-5xl font-black">#{{ receiptOrder.queue_number }}</p><h2 id="order-success-title" class="mt-2 text-xl font-black">{{ receiptOrder.payment_method === 'qris' ? 'Pembayaran QRIS berhasil' : 'Silakan bayar ke owner' }}</h2><p class="mt-2 text-sm text-stone-500">{{ receiptOrder.payment_method === 'qris' ? 'File struk PDF sudah diunduh. Tunjukkan nomor antrean saat mengambil pesanan.' : 'Pesanan diproses setelah pembayaran tunai diterima.' }}</p><p v-if="receiptError" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ receiptError }}</p><button v-if="receiptOrder.payment_method === 'qris' && receiptError" class="mt-4 rounded-xl border border-orange-200 px-5 py-3 font-bold text-chic-orange" type="button" @click="retryReceiptDownload">Unduh struk PDF lagi</button></div><form v-if="!reviewSubmitted" class="mt-6 border-t border-orange-100 pt-5" @submit.prevent="submitReview"><p class="text-center text-xs font-bold uppercase tracking-[0.14em] text-chic-orange">Bantu kami jadi lebih baik</p><h3 class="mt-1 text-center text-lg font-black">Bagaimana pesananmu?</h3><div class="mt-3 flex justify-center gap-1" role="radiogroup" aria-label="Pilih rating"><button v-for="rating in 5" :key="rating" class="px-1 text-3xl" :class="rating <= reviewRating ? 'text-amber-500' : 'text-stone-300'" type="button" role="radio" :aria-checked="reviewRating === rating" :aria-label="`${rating} bintang`" @click="reviewRating = rating">★</button></div><label class="mt-3 block text-sm font-bold">Nama <span class="font-normal text-stone-400">(opsional)</span><input v-model="reviewName" class="mt-1 w-full rounded-xl border border-stone-200 px-3 py-2.5 font-normal" maxlength="30" placeholder="Nama Anda"></label><label class="mt-3 block text-sm font-bold">Komentar <span class="font-normal text-stone-400">(opsional)</span><textarea v-model="reviewComment" class="mt-1 w-full resize-none rounded-xl border border-stone-200 px-3 py-2.5 font-normal" rows="2" maxlength="240" placeholder="Ceritakan pengalaman Anda"></textarea></label><p v-if="reviewError" class="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ reviewError }}</p><button class="mt-4 w-full rounded-xl bg-chic-orange px-4 py-3 font-bold text-white disabled:bg-stone-300" type="submit" :disabled="!reviewRating || reviewSubmitting">{{ reviewSubmitting ? 'Mengirim ulasan…' : 'Kirim ulasan' }}</button></form><div v-else class="mt-6 rounded-2xl bg-emerald-50 p-4 text-center text-sm font-bold text-emerald-800">Terima kasih, ulasan Anda sudah terkirim.</div><div class="mt-4 flex justify-center"><button class="rounded-xl border border-stone-200 px-5 py-2.5 text-sm font-bold text-stone-600" type="button" @click="receiptOrder = null">{{ reviewSubmitted ? 'Selesai' : 'Lewati ulasan' }}</button></div></section></div>
  </main>
</template>