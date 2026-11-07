bool get isNativeRtspSupported => false;

Future<bool> canReachRtspPort(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 850),
}) async =>
    false;
