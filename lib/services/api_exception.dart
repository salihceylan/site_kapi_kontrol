class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  SessionExpiredException([super.message = 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'])
      : super(statusCode: 401);
}
