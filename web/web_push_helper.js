// Dart tarafindan cagrilan tarayici bildirimi yardimcisi (window.kapiWebPush). Firebase kullanmaz.
(function () {
  function b64ToBytes(b64) {
    var pad = '='.repeat((4 - (b64.length % 4)) % 4);
    var raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  function reg() { return navigator.serviceWorker.register('push_sw.js').then(function () { return navigator.serviceWorker.ready; }); }
  window.kapiWebPush = {
    supported: function () {
      return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
    },
    // Izin ister, abone olur; abonelik JSON metnini dondurur (izin yoksa null).
    subscribe: function (publicKey) {
      if (!window.kapiWebPush.supported()) return Promise.resolve(null);
      return Notification.requestPermission().then(function (p) {
        if (p !== 'granted') return null;
        return reg().then(function (r) {
          return r.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToBytes(publicKey) });
        }).then(function (sub) { return JSON.stringify(sub.toJSON()); });
      });
    },
    // Aboneligi kaldirir; eski endpoint adresini dondurur.
    unsubscribe: function () {
      if (!window.kapiWebPush.supported()) return Promise.resolve(null);
      return navigator.serviceWorker.getRegistration('push_sw.js').then(function (r) {
        if (!r) return null;
        return r.pushManager.getSubscription().then(function (sub) {
          if (!sub) return null;
          var endpoint = sub.endpoint;
          return sub.unsubscribe().then(function () { return endpoint; });
        });
      });
    },
    currentEndpoint: function () {
      if (!window.kapiWebPush.supported()) return Promise.resolve(null);
      return navigator.serviceWorker.getRegistration('push_sw.js').then(function (r) {
        return r ? r.pushManager.getSubscription().then(function (s) { return s ? s.endpoint : null; }) : null;
      });
    },
  };
})();
