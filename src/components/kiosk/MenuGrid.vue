<script setup>
import { MENU_SIZES } from '../../constants/menu'

defineProps({ ingredients: { type: Array, default: () => [] } })
const emit = defineEmits(['select'])
const stockFor = (ingredients, id) => ingredients.find((ingredient) => ingredient.id === id)?.stock ?? 0
</script>

<template>
  <section aria-labelledby="menu-title">
    <div class="mb-5"><p class="text-sm font-bold uppercase tracking-[0.18em] text-chic-orange">Pilih ukuran</p><h1 id="menu-title" class="mt-1 text-3xl font-black tracking-tight sm:text-4xl">Chicken Steak untuk harimu.</h1><p class="mt-2 text-sm text-stone-600">Pilih ukuran, lalu tentukan saus dan karbohidrat favoritmu.</p></div>
    <div class="grid gap-4 sm:grid-cols-3">
      <article v-for="size in MENU_SIZES" :key="size.id" class="rounded-3xl border border-orange-100 bg-white p-5 shadow-sm"><div class="flex h-20 w-20 items-center justify-center rounded-2xl bg-orange-50 text-5xl">🍗</div><h2 class="mt-5 text-lg font-extrabold">{{ size.label }}</h2><p class="mt-1 text-sm text-stone-500">Porsi chicken steak pilihan.</p><p class="mt-4 text-xl font-black text-chic-orange">Rp{{ size.price.toLocaleString('id-ID') }}</p><button class="mt-5 w-full rounded-xl px-4 py-3 text-sm font-bold transition disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-stone-400" :class="stockFor(ingredients, size.chickenIngredientId) > 0 ? 'bg-chic-orange text-white hover:bg-chic-orange-dark' : ''" :disabled="stockFor(ingredients, size.chickenIngredientId) <= 0" @click="emit('select', size.id)">{{ stockFor(ingredients, size.chickenIngredientId) > 0 ? 'Pilih menu' : 'Stok habis' }}</button></article>
    </div>
  </section>
</template>
