import 'package:flutter/foundation.dart';

/// Compile-time base URL for the OCR HTTP API (no trailing slash).
///
/// Override for local dev:
/// `flutter run -d chrome --dart-define=OCR_BASE_URL=http://localhost:5010`
const String _kOcrBaseUrlEnv = String.fromEnvironment('OCR_BASE_URL');

const String _kMagicDefaultBaseUrl = 'http://128.180.121.230:5010';

String _trimTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

String _webDefaultBaseUrl() {
  // When running Flutter web, default to the same host as the app (port 5010).
  // This avoids "works on device but not in browser" issues due to CORS / LAN IPs.
  final base = Uri.base;
  final scheme = base.scheme.isEmpty ? 'http' : base.scheme;
  final host = base.host.isEmpty ? 'localhost' : base.host;
  return '$scheme://$host:5010';
}

/// Resolved base URL (no trailing slash).
String ocrServiceBaseUrl() {
  final trimmedEnv = _trimTrailingSlash(_kOcrBaseUrlEnv.trim());
  if (trimmedEnv.isNotEmpty) return trimmedEnv;
  // For web builds deployed on HTTPS hosts (e.g., Vercel), calling an HTTP backend
  // directly often fails due to mixed-content restrictions. Default to a same-origin
  // proxy path when no OCR_BASE_URL is provided at build time.
  if (kIsWeb) {
    final base = Uri.base;
    return _trimTrailingSlash('${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}/api/ocr');
  }
  final fallback = _kMagicDefaultBaseUrl;
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
