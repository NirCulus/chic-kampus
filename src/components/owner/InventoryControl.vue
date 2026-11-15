<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useInventory } from '../../composables/useInventory'
import { requireSupabase } from '../../supabase'

const { ingredients, stockLedger, loading, error, fetchIngredients, fetchStockLedger, isLowStock, adjustStock } = useInventory()
const selectedIngredient = ref(null)
const quantity = ref(1)
const changeType = ref('restock')
const notes = ref('')
const submitting = ref(false)
const savingCostId = ref(null)
const costDrafts = ref({})
const actionError = ref('')
let inventoryChannel = null
const date = (value) => new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))

async function refresh() {
  try {
    await Promise.all([fetchIngredients(), fetchStockLedger()])
    const { data: costs, error: costError } = await requireSupabase().from('ingredient_costs').select('ingredient_id, unit_cost')
    if (costError) throw costError
    costDrafts.value = Object.fromEntries((costs ?? []).map((cost) => [cost.ingredient_id, cost.unit_cost]))
  } catch (requestError) { actionError.value = requestError.message || 'Data stok belum dapat dimuat.' }
}
function openAdjustment(ingredient) { selectedIngredient.value = ingredient; quantity.value = 1; changeType.value = 'restock'; notes.value = ''; actionError.value = '' }
function closeAdjustment() { selectedIngredient.value = null; actionError.value = '' }
async function submitAdjustment() {
  if (!selectedIngredient.value || !Number.isInteger(Number(quantity.value)) || Number(quantity.value) < 1) return
  submitting.value = true; actionError.value = ''
  try {
    const signedQuantity = changeType.value === 'waste' ? -Number(quantity.value) : Number(quantity.value)
    await adjustStock({ ingredientId: selectedIngredient.value.id, quantity: signedQuantity, changeType: changeType.value, notes: notes.value.trim() || null })
    await refresh(); closeAdjustment()
  } catch (requestError) { actionError.value = requestError.message || 'Penyesuaian stok gagal.' } finally { submitting.value = false }
}
async function saveUnitCost(ingredient) {
  const cost = Number(costDrafts.value[ingredient.id])
  if (!Number.isInteger(cost) || cost < 0 || savingCostId.value) return
  savingCostId.value = ingredient.id
  actionError.value = ''
  try {
    const { error: requestError } = await requireSupabase().rpc('set_ingredient_unit_cost', {
      p_ingredient_id: ingredient.id,
      p_unit_cost: cost,
    })
    if (requestError) throw requestError
    await fetchIngredients()
    costDrafts.value[ingredient.id] = cost
  } catch (requestError) {
    actionError.value = requestError.message || 'Harga HPP belum dapat disimpan.'
  } finally {
    savingCostId.value = null
  }
}
onMounted(async () => {
  await refresh()
  inventoryChannel = requireSupabase().channel('owner-stock').on('postgres_changes', { event: '*', schema: 'public', table: 'ingredients' }, refresh).on('postgres_changes', { event: '*', schema: 'public', table: 'stock_ledger' }, refresh).subscribe()
})
onBeforeUnmount(() => { if (inventoryChannel) requireSupabase().removeChannel(inventoryChannel) })
</script>

<template>
  <section>
    <div class="flex flex-wrap items-end justify-between gap-3"><div><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Persediaan</p><h2 class="mt-1 text-xl font-black">Kontrol stok bahan</h2><p class="mt-1 text-sm text-stone-500">Perubahan dari Kiosk dan Owner diperbarui otomatis.</p></div><button class="rounded-xl border border-orange-200 bg-white px-4 py-2 text-sm font-bold text-chic-orange" :disabled="loading" type="button" @click="refresh">{{ loading ? 'Memuat…' : 'Muat ulang' }}</button></div>
    <p v-if="actionError || error" class="mt-4 rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">{{ actionError || error?.message }}</p>
    <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-3"><article v-for="ingredient in ingredients" :key="ingredient.id" class="rounded-2xl border bg-white p-4 shadow-sm" :class="isLowStock(ingredient) ? 'border-amber-300' : 'border-orange-100'"><div class="flex justify-between gap-3"><div><h3 class="font-bold">{{ ingredient.name }}</h3><p class="mt-1 text-xs text-stone-500">Minimum {{ ingredient.min_stock }} {{ ingredient.unit_type }}</p></div><span v-if="isLowStock(ingredient)" class="h-fit rounded-full bg-amber-100 px-2 py-1 text-[10px] font-bold text-amber-800">Menipis</span></div><p class="mt-5 text-3xl font-black" :class="isLowStock(ingredient) ? 'text-amber-700' : 'text-chic-orange'">{{ ingredient.stock }}<span class="ml-1 text-sm font-medium text-stone-500">{{ ingredient.unit_type }}</span></p><div class="mt-4 flex items-end gap-2"><label class="min-w-0 flex-1 text-xs font-bold text-stone-600">HPP / {{ ingredient.unit_type }}<input v-model.number="costDrafts[ingredient.id]" class="mt-1 w-full rounded-lg border border-stone-200 px-2 py-2 text-sm" min="0" step="1" type="number"></label><button class="rounded-lg border border-orange-200 px-3 py-2 text-xs font-bold text-chic-orange disabled:opacity-50" type="button" :disabled="savingCostId === ingredient.id" @click="saveUnitCost(ingredient)">{{ savingCostId === ingredient.id ? 'Simpan…' : 'Simpan HPP' }}</button></div><button class="mt-3 w-full rounded-xl border border-orange-200 px-3 py-2 text-sm font-bold text-chic-orange" type="button" @click="openAdjustment(ingredient)">Atur stok</button></article></div>
    <section class="mt-8"><h3 class="text-lg font-black">Riwayat stok terbaru</h3><div class="mt-3 overflow-x-auto rounded-2xl border border-orange-100 bg-white"><table class="w-full min-w-[640px] text-left text-sm"><thead class="bg-orange-50 text-xs uppercase tracking-wide text-stone-500"><tr><th class="px-4 py-3">Waktu</th><th class="px-4 py-3">Bahan</th><th class="px-4 py-3">Perubahan</th><th class="px-4 py-3">Pesanan</th><th class="px-4 py-3">Catatan</th></tr></thead><tbody class="divide-y divide-stone-100"><tr v-for="entry in stockLedger" :key="entry.id"><td class="px-4 py-3 text-xs text-stone-500">{{ date(entry.created_at) }}</td><td class="px-4 py-3 font-medium">{{ entry.ingredients?.name }}</td><td class="px-4 py-3 font-bold" :class="entry.quantity > 0 ? 'text-emerald-700' : 'text-red-700'">{{ entry.quantity > 0 ? '+' : '' }}{{ entry.quantity }}</td><td class="px-4 py-3">{{ entry.orders?.queue_number ? '#' + entry.orders.queue_number : '—' }}</td><td class="px-4 py-3 text-stone-500">{{ entry.notes || '—' }}</td></tr><tr v-if="!stockLedger.length"><td colspan="5" class="px-4 py-8 text-center text-stone-500">Belum ada riwayat stok.</td></tr></tbody></table></div></section>
    <div v-if="selectedIngredient" class="screen-only fixed inset-0 z-40 grid place-items-center bg-black/50 p-4" @click.self="closeAdjustment"><form class="w-full max-w-md rounded-3xl bg-white p-6 shadow-2xl" @submit.prevent="submitAdjustment"><div class="flex justify-between gap-4"><div><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Penyesuaian stok</p><h3 class="mt-1 text-xl font-black">{{ selectedIngredient.name }}</h3><p class="mt-1 text-sm text-stone-500">Stok sekarang: {{ selectedIngredient.stock }} {{ selectedIngredient.unit_type }}</p></div><button class="grid h-9 w-9 place-items-center rounded-full bg-stone-100 text-lg font-bold" type="button" @click="closeAdjustment">×</button></div><label class="mt-5 block text-sm font-bold">Jenis perubahan<select v-model="changeType" class="mt-2 w-full rounded-xl border border-stone-200 bg-white px-3 py-3"><option value="restock">Tambah stok</option><option value="waste">Kurangi stok</option></select></label><label class="mt-4 block text-sm font-bold">Jumlah<input v-model.number="quantity" min="1" class="mt-2 w-full rounded-xl border border-stone-200 px-3 py-3" type="number" required></label><label class="mt-4 block text-sm font-bold">Catatan <span class="font-normal text-stone-400">(opsional)</span><input v-model="notes" class="mt-2 w-full rounded-xl border border-stone-200 px-3 py-3" type="text" maxlength="160" placeholder="Contoh: stok kiriman pagi"></label><p v-if="actionError" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ actionError }}</p><button class="mt-6 w-full rounded-xl bg-chic-orange px-4 py-3 font-bold text-white disabled:bg-stone-300" :disabled="submitting" type="submit">{{ submitting ? 'Menyimpan…' : 'Simpan perubahan' }}</button></form></div>
  </section>
</template>