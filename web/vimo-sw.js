importScripts('vimo-shell.js');

const cachePrefix = 'vimo-shell-';
const cacheName = cachePrefix + self.vimoShell.version;
const root = self.registration.scope;
const paths = new Set(self.vimoShell.paths.map(path => new URL(path, root).href));
const index = new URL('index.html', root).href;

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(cacheName);
    await cache.addAll([...paths].map(url => new Request(url, { cache: 'reload' })));
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name =>
      (name.startsWith(cachePrefix) && name !== cacheName) ||
      ['flutter-app-manifest', 'flutter-temp-cache', 'flutter-app-cache'].includes(name)
    ).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  const scope = new URL(root);
  if (url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname) ||
      url.pathname.startsWith(scope.pathname + '__/')) return;
  url.search = '';
  const key = request.mode === 'navigate' ? index : url.href;
  if (!paths.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    return (await cache.match(key)) || fetch(request);
  })());
});
