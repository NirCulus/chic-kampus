import { computed, ref } from 'vue'
import { isSupabaseConfigured, requireSupabase } from '../supabase'

const session = ref(null)
const initialized = ref(false)
let initializationPromise = null
let subscription = null

export async function initializeAuth() {
  if (initializationPromise) return initializationPromise
  initializationPromise = (async () => {
    if (!isSupabaseConfigured) {
      initialized.value = true
      return null
    }
    const client = requireSupabase()
    const { data, error } = await client.auth.getSession()
    if (error) throw error
    session.value = data.session
    initialized.value = true
    subscription = client.auth.onAuthStateChange((_event, nextSession) => {
      session.value = nextSession
    }).data.subscription
    return session.value
  })()
  return initializationPromise
}

export async function getOwnerSession() {
  await initializeAuth()
  return session.value
}

export function useAuth() {
  const user = computed(() => session.value?.user ?? null)
  const isAuthenticated = computed(() => Boolean(session.value))
  async function signIn(email, password) {
    const { data, error } = await requireSupabase().auth.signInWithPassword({ email, password })
    if (error) throw error
    session.value = data.session
    return data.session
  }
  async function signOut() {
    const { error } = await requireSupabase().auth.signOut()
    if (error) throw error
    session.value = null
  }
  return { session, user, initialized, isAuthenticated, signIn, signOut }
}
