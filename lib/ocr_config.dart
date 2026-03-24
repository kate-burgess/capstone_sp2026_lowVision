/// Compile-time base URL for the OCR HTTP API (no trailing slash).
///
/// Defaults to the MAGIC GPU server's direct IP.
/// Override for local dev:
/// `flutter run --dart-define=OCR_BASE_URL=http://localhost:5010`
const String _kOcrBaseUrl = String.fromEnvironment(
  'OCR_BASE_URL',
  defaultValue: 'http://128.180.121.230:5010',
);

String _trimTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Resolved base URL (no trailing slash).
String ocrServiceBaseUrl() => _trimTrailingSlash(_kOcrBaseUrl);

/// Both local and MAGIC servers use the same `/extract-text` route.
String get ocrMultipartPath => '/extract-text';

/// Full URI for multipart image upload (field name `image`).
Uri ocrMultipartUri() =>
    Uri.parse('${ocrServiceBaseUrl()}$ocrMultipartPath');

/// URI for saving the image to the MAGIC server's Images_2026 folder.
Uri uploadUri() => Uri.parse('${ocrServiceBaseUrl()}/upload');
