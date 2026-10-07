import { onBeforeUnmount } from 'vue'

const ACTIVITY_EVENTS = ['pointerdown', 'keydown', 'touchstart']

export function useIdleTimer(onIdle, timeoutMs = 120_000) {
  let timerId
  function reset() { window.clearTimeout(timerId); timerId = window.setTimeout(onIdle, timeoutMs) }
  function start() { ACTIVITY_EVENTS.forEach((eventName) => window.addEventListener(eventName, reset, { passive: true })); reset() }
  function stop() { window.clearTimeout(timerId); ACTIVITY_EVENTS.forEach((eventName) => window.removeEventListener(eventName, reset)) }
  onBeforeUnmount(stop)
  return { start, stop, reset }
}
