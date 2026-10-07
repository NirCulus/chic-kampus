import { createRouter, createWebHistory } from 'vue-router'
import KioskView from '../views/KioskView.vue'
import OwnerView from '../views/OwnerView.vue'
import PinLogin from '../components/owner/PinLogin.vue'
import { getOwnerSession } from '../composables/useAuth'

async function requireOwner() {
  return (await getOwnerSession()) ? true : { name: 'OwnerLogin' }
}

async function redirectAuthenticatedOwner() {
  return (await getOwnerSession()) ? { name: 'Owner' } : true
}

const routes = [
  {
    path: '/',
    redirect: '/kiosk',
  },
  {
    path: '/kiosk',
    name: 'Kiosk',
    component: KioskView,
  },
  {
    path: '/owner',
    name: 'Owner',
    component: OwnerView,
    beforeEnter: requireOwner,
  },
  {
    path: '/owner/login',
    name: 'OwnerLogin',
    component: PinLogin,
    beforeEnter: redirectAuthenticatedOwner,
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
