// Push on this device (gaia#15): where it stands and how to turn it on.
// Content-free: the service worker shows who wrote, never what.

export type PushState =
  | 'unsupported' // no service worker, push or notifications here
  | 'install' // an iPhone or iPad not running from the Home Screen
  | 'denied' // the device's settings block notifications for Oneiroi
  | 'ready' // can be turned on
  | 'on'; // this device is subscribed

const WORKER = '/client/sw.js';
const NAME_KEY = '/client/push-name';

function supported(): boolean {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

function appleWithoutHomeScreen(): boolean {
  const apple = /iPhone|iPad|iPod/.test(navigator.userAgent);
  const standalone =
    (navigator as Navigator & { standalone?: boolean }).standalone === true ||
    (typeof window.matchMedia === 'function' && window.matchMedia('(display-mode: standalone)').matches);
  return apple && !standalone;
}

// Registered on every load, so a push can be shown whether or not the
// page is open.
export function registerWorker(): void {
  if (supported()) void navigator.serviceWorker.register(WORKER, { scope: '/client/' }).catch(() => undefined);
}

async function subscription(): Promise<PushSubscription | null> {
  const reg = await navigator.serviceWorker.getRegistration('/client/');
  return reg ? reg.pushManager.getSubscription() : null;
}

export async function pushState(): Promise<PushState> {
  if (appleWithoutHomeScreen()) return 'install';
  if (!supported()) return 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  return (await subscription().catch(() => null)) ? 'on' : 'ready';
}

function keyBytes(base64url: string): ArrayBuffer {
  const pad = '='.repeat((4 - (base64url.length % 4)) % 4);
  const raw = atob((base64url + pad).replace(/-/g, '+').replace(/_/g, '/'));
  const bytes = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

// Asks the device, then subscribes: the endpoint is what the server keeps.
// The name is left where the worker reads it, so the notification can
// say who wrote without the push carrying it.
export async function turnOn(publicKey: string, residentName: string): Promise<string> {
  if ((await Notification.requestPermission()) !== 'granted') throw new Error('Notifications were not allowed.');
  const reg = await navigator.serviceWorker.register(WORKER, { scope: '/client/' });
  await navigator.serviceWorker.ready;
  const cache = await caches.open('oneiroi');
  await cache.put(NAME_KEY, new Response(residentName));
  const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) });
  return sub.endpoint;
}

export async function turnOff(): Promise<string | null> {
  const sub = await subscription();
  if (!sub) return null;
  await sub.unsubscribe();
  return sub.endpoint;
}
