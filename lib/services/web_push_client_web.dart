// Tarayıcı bildirimi (VAPID) köprüsü: web/web_push_helper.js içindeki window.kapiWebPush çağrılır.
import 'dart:js_interop';

@JS('kapiWebPush.supported')
external bool _supported();

@JS('kapiWebPush.subscribe')
external JSPromise<JSString?> _subscribe(String publicKey);

@JS('kapiWebPush.unsubscribe')
external JSPromise<JSString?> _unsubscribe();

@JS('kapiWebPush.currentEndpoint')
external JSPromise<JSString?> _currentEndpoint();

bool webPushSupported() {
  try {
    return _supported();
  } catch (_) {
    return false;
  }
}

Future<String?> webPushSubscribe(String publicKey) async => (await _subscribe(publicKey).toDart)?.toDart;

Future<String?> webPushUnsubscribe() async => (await _unsubscribe().toDart)?.toDart;

Future<String?> webPushCurrentEndpoint() async => (await _currentEndpoint().toDart)?.toDart;
