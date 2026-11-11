// Oneiroi's service worker (gaia#15): content-free pushes. A push carries
// nothing, so nothing the resident said ever passes through a push
// service. A push comes for two reasons (she wrote, gaia#15; something
// first waits on you, brain#77) and carries neither, so the notification
// names her, by the name the page left here when it subscribed, says
// only that there's something new, and opens the house when tapped.
const NAME_KEY = '/client/push-name';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

async function residentName() {
  try {
    const cache = await caches.open('oneiroi');
    const hit = await cache.match(NAME_KEY);
    return hit ? (await hit.text()) || 'Your resident' : 'Your resident';
  } catch {
    return 'Your resident';
  }
}

self.addEventListener('push', (event) => {
  event.waitUntil(
    residentName().then((name) =>
      self.registration.showNotification(name, {
        body: 'A letter, or something waiting on you.',
        tag: 'oneiroi',
      }),
    ),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const w of windows) if ('focus' in w) return w.focus();
      return self.clients.openWindow('/client/index.html');
    }),
  );
});
