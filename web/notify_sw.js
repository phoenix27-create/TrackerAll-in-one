// LifeTrack notification service worker.
// * Shows notifications the open app asks for (needed on iPhone home-screen
//   apps and Android Chrome, where `new Notification()` is not allowed).
// * Receives Web Push messages, so notifications also arrive when the app is
//   closed (iPhone: Home Screen app on iOS 16.4+).
// It does not cache anything.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'LifeTrack';
  event.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || '',
      tag: data.tag || undefined,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: { url: data.url || '/' },
    }),
  );
});

// Tapping a notification opens (or focuses) the app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return self.clients.openWindow(url);
    }),
  );
});
