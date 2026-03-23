/// Compile-time base URL for the OCR HTTP API (no trailing slash).
///
/// Defaults to the course MAGIC deployment. Override for local [ocr_server.py]:
/// `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5001`
const String _kOcrBaseUrl = String.fromEnvironment(
  'OCR_BASE_URL',
  defaultValue:
      'http://magic01.cse.lehigh.edu/user/lowvisioncapstone/lab',
);

String _trimTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

bool _isLocalDevHost(String base) {
  final u = base.toLowerCase();
  return u.contains('localhost') ||
      u.contains('127.0.0.1') ||
      u.contains('10.0.2.2');
}

/// Resolved base URL (no trailing slash).
String ocrServiceBaseUrl() => _trimTrailingSlash(_kOcrBaseUrl);

/// POST path: `/ocr` on MAGIC; `/extract-text` for the local Flask server.
String get ocrMultipartPath =>
    _isLocalDevHost(ocrServiceBaseUrl()) ? '/extract-text' : '/ocr';

/// Full URI for multipart image upload (field name `image`).
Uri ocrMultipartUri() =>
    Uri.parse('${ocrServiceBaseUrl()}$ocrMultipartPath');
