<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import FinancialReports from '../components/owner/FinancialReports.vue'
import InventoryControl from '../components/owner/InventoryControl.vue'
import QueueManager from '../components/owner/QueueManager.vue'
import CustomerReviews from '../components/owner/CustomerReviews.vue'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const { user, signOut } = useAuth()
const activeTab = ref('queue')
const tabs = [
  { id: 'queue', label: 'Antrean' },
  { id: 'inventory', label: 'Stok & HPP' },
  { id: 'finance', label: 'Keuangan & penjualan' },
  { id: 'reviews', label: 'Ulasan' },
]
async function logout() { await signOut(); router.replace({ name: 'OwnerLogin' }) }
</script>
<template>
  <main class="min-h-screen bg-chic-cream text-chic-ink"><header class="border-b border-orange-100 bg-white"><div class="mx-auto flex max-w-7xl flex-wrap items-center gap-4 px-5 py-4 sm:px-7"><div><p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Chic Kampus · Owner</p><h1 class="mt-1 text-2xl font-black">Dashboard operasional</h1></div><div class="ml-auto text-right"><p class="text-xs text-stone-500">{{ user?.email }}</p><button class="mt-1 text-sm font-bold text-chic-orange" type="button" @click="logout">Keluar</button></div></div></header><div class="mx-auto max-w-7xl px-5 py-6 sm:px-7"><nav class="flex gap-2 overflow-x-auto border-b border-orange-100 pb-3" aria-label="Navigasi dashboard"><button v-for="tab in tabs" :key="tab.id" class="whitespace-nowrap rounded-xl px-4 py-2.5 text-sm font-bold transition" :class="activeTab === tab.id ? 'bg-chic-orange text-white' : 'bg-white text-stone-600 ring-1 ring-stone-200'" type="button" @click="activeTab = tab.id">{{ tab.label }}</button></nav><div class="mt-6"><QueueManager v-if="activeTab === 'queue'" /><InventoryControl v-else-if="activeTab === 'inventory'" /><FinancialReports v-else-if="activeTab === 'finance'" /><CustomerReviews v-else-if="activeTab === 'reviews'" /></div></div></main>
</template>