class ApiException implements Exception {
  ApiException(this.message);

  final String message;
}
