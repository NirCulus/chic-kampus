<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../../composables/useAuth'

const router = useRouter()
const { signIn } = useAuth()
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMessage = ref('')

async function submit() {
  if (!email.value || !password.value || loading.value) return
  loading.value = true
  errorMessage.value = ''
  try {
    await signIn(email.value.trim(), password.value)
    router.replace({ name: 'Owner' })
  } catch (error) {
    errorMessage.value = error.message || 'Login tidak berhasil. Periksa email dan password.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="grid min-h-screen place-items-center bg-chic-cream p-5 text-chic-ink">
    <form class="w-full max-w-sm rounded-3xl border border-orange-100 bg-white p-7 shadow-sm" @submit.prevent="submit">
      <p class="text-xs font-bold uppercase tracking-[0.16em] text-chic-orange">Akses terbatas</p>
      <h1 class="mt-2 text-2xl font-black">Login Owner</h1>
      <p class="mt-2 text-sm text-stone-500">Masuk dengan akun Owner Chic Kampus.</p>
      <label class="mt-6 block text-sm font-bold">Email
        <input v-model="email" class="mt-2 w-full rounded-xl border border-stone-200 px-4 py-3 outline-none focus:border-chic-orange" type="email" autocomplete="email" required>
      </label>
      <label class="mt-4 block text-sm font-bold">Password
        <input v-model="password" class="mt-2 w-full rounded-xl border border-stone-200 px-4 py-3 outline-none focus:border-chic-orange" type="password" autocomplete="current-password" required>
      </label>
      <p v-if="errorMessage" class="mt-4 rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">{{ errorMessage }}</p>
      <button class="mt-6 w-full rounded-xl bg-chic-orange px-5 py-3 font-bold text-white disabled:bg-stone-300" :disabled="loading" type="submit">
        {{ loading ? 'Memeriksa akun…' : 'Masuk ke Dashboard' }}
      </button>
    </form>
  </main>
</template>
