import { computed, ref } from 'vue'
import { getCarb, getSauce, getSize, PACKAGING_INGREDIENT_ID } from '../constants/menu'
import { requireSupabase } from '../supabase'

const ingredients = ref([])
const stockLedger = ref([])
const loading = ref(false)
const error = ref(null)

export function useInventory() {
  const byId = computed(() => new Map(ingredients.value.map((ingredient) => [ingredient.id, ingredient])))
  async function fetchIngredients() {
    loading.value = true; error.value = null
    const { data, error: requestError } = await requireSupabase().from('ingredients').select('*').order('name')
    loading.value = false
    if (requestError) { error.value = requestError; throw requestError }
    ingredients.value = data ?? []; return ingredients.value
  }
  async function fetchStockLedger(limit = 30) {
    const { data, error: requestError } = await requireSupabase().from('stock_ledger').select('*, ingredients(name), orders(queue_number)').order('created_at', { ascending: false }).limit(limit)
    if (requestError) throw requestError
    stockLedger.value = data ?? []; return stockLedger.value
  }
  const isLowStock = (ingredient) => ingredient.stock <= ingredient.min_stock
  function isItemAvailable({ size, sauceVariant, carbType, qty = 1 }) {
    const ids = [getSize(size)?.chickenIngredientId, getSauce(sauceVariant)?.ingredientId, getCarb(carbType)?.ingredientId, PACKAGING_INGREDIENT_ID]
    return ids.every((id) => id && (byId.value.get(id)?.stock ?? 0) >= qty)
  }
  function isCartAvailable(cart) {
    const required = new Map()
    for (const item of cart) [getSize(item.size)?.chickenIngredientId, getSauce(item.sauceVariant)?.ingredientId, getCarb(item.carbType)?.ingredientId, PACKAGING_INGREDIENT_ID].forEach((id) => required.set(id, (required.get(id) ?? 0) + item.qty))
    return [...required].every(([id, qty]) => (byId.value.get(id)?.stock ?? 0) >= qty)
  }
  async function adjustStock({ ingredientId, quantity, changeType, notes = null }) {
    const { data, error: requestError } = await requireSupabase().rpc('adjust_stock', { p_ingredient_id: ingredientId, p_quantity: quantity, p_change_type: changeType, p_notes: notes })
    if (requestError) throw requestError
    const index = ingredients.value.findIndex((item) => item.id === ingredientId)
    if (index !== -1) ingredients.value[index] = data
    return data
  }
  return { ingredients, stockLedger, byId, loading, error, fetchIngredients, fetchStockLedger, isLowStock, isItemAvailable, isCartAvailable, adjustStock }
}