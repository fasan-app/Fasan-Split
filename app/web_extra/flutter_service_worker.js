// Fasan Split – replaces the service worker of older web builds (Flutter's, removed 04.11.). Browsers fetch this file
// again on their own; then it clears the old caches and unregisters itself, coi-serviceworker.js takes over.
// Old cached builds can no longer hide a fix (an invitee landed in an old app). MPL-2.0
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) {
      if (!k.startsWith('fasan-models')) await caches.delete(k);
    }
    await self.registration.unregister();
    for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url);
  })());
});
