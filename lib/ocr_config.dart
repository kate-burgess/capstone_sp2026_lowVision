import 'package:flutter/foundation.dart';

/// Compile-time base URL for the OCR HTTP API (no trailing slash).
///
/// Override for local dev:
/// `flutter run -d chrome --dart-define=OCR_BASE_URL=http://localhost:5010`
const String _kOcrBaseUrlEnv = String.fromEnvironment('OCR_BASE_URL');

const String _kMagicDefaultBaseUrl = 'http://128.180.121.230:5010';

String _trimTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

bool _isLocalWebHost(String host) {
  final h = host.toLowerCase();
  return h.isEmpty || h == 'localhost' || h == '127.0.0.1' || h == '[::1]';
}

/// Web: only local dev uses same-host port 5010. Static hosts (e.g. Vercel)
/// have no OCR on `:5010`—set [OCR_BASE_URL] at **build** time.
String _webOcrFallbackBaseUrl() {
  final base = Uri.base;
  final scheme = base.scheme.isEmpty ? 'http' : base.scheme;
  final host = base.host.isEmpty ? 'localhost' : base.host;
  if (_isLocalWebHost(host)) {
    return '$scheme://$host:5010';
  }
  return _kMagicDefaultBaseUrl;
}

/// `true` if `flutter build web --dart-define=OCR_BASE_URL=...` was used.
bool ocrBaseUrlSetAtBuildTime() =>
    _trimTrailingSlash(_kOcrBaseUrlEnv.trim()).isNotEmpty;

/// Web only: deployed static site (not localhost) without `--dart-define` OCR URL.
bool ocrWebMissingBuildTimeUrl() {
  if (!kIsWeb) return false;
  if (ocrBaseUrlSetAtBuildTime()) return false;
  final host = Uri.base.host;
  return !_isLocalWebHost(host);
}

/// Resolved base URL (no trailing slash).
String ocrServiceBaseUrl() {
  final trimmedEnv = _trimTrailingSlash(_kOcrBaseUrlEnv.trim());
  if (trimmedEnv.isNotEmpty) return trimmedEnv;
  final fallback = kIsWeb ? _webDefaultBaseUrl() : _kMagicDefaultBaseUrl;
  return _trimTrailingSlash(fallback);
}

/// Both local and MAGIC servers use the same `/extract-text` route.
String get ocrMultipartPath => '/extract-text';

Uri _proxyUri(String path) {
  // Proxy endpoint: /api/ocr?path=/extract-text
  final base = Uri.base;
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return Uri.parse('$origin/api/ocr').replace(queryParameters: {'path': path});
}

/// Full URI for multipart image upload (field name `image`).
Uri ocrMultipartUri() {
  final base = ocrServiceBaseUrl();
  if (kIsWeb && base.endsWith('/api/ocr')) {
    return _proxyUri('/extract-text');
  }
  return Uri.parse('$base$ocrMultipartPath');
}

/// URI for saving the image to the MAGIC server's Images_2026 folder.
Uri uploadUri() {
  final base = ocrServiceBaseUrl();
  if (kIsWeb && base.endsWith('/api/ocr')) {
    return _proxyUri('/upload');
  }
  return Uri.parse('$base/upload');
}

/// URI for VLM predictions (image + question -> answer).
Uri vlmPredictUri() {
  final base = ocrServiceBaseUrl();
  if (kIsWeb && base.endsWith('/api/ocr')) {
    return _proxyUri('/predict');
  }
  return Uri.parse('$base/predict');
}

/// URI for YOLO object detections (image -> label list).
Uri yoloDetectUri() {
  final base = ocrServiceBaseUrl();
  if (kIsWeb && base.endsWith('/api/ocr')) {
    return _proxyUri('/detect-yolo');
  }
  return Uri.parse('$base/detect-yolo');
}
