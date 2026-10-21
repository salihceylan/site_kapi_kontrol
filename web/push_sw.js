// Tarayici bildirimi (VAPID web push) servis calisani. Yalniz kisa baslik/govde gosterir; kisisel ayrinti sunucudan gelmez.
self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = {}; }
  var title = String(data.title || 'Bildirim').slice(0, 80);
  var body = String(data.body || '').slice(0, 200);
  event.waitUntil(self.registration.showNotification(title, { body: body, icon: 'icons/Icon-192.png', data: { url: data.url || '/' } }));
});
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({ type: 'window' }).then(function (list) {
    for (var i = 0; i < list.length; i++) { if ('focus' in list[i]) return list[i].focus(); }
    return self.clients.openWindow('/');
  }));
});
