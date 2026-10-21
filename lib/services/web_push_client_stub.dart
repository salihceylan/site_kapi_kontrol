/// Web dışı platformlarda tarayıcı bildirimi yoktur.
bool webPushSupported() => false;

Future<String?> webPushSubscribe(String publicKey) async => null;

Future<String?> webPushUnsubscribe() async => null;

Future<String?> webPushCurrentEndpoint() async => null;
