// Stub for non-web platforms. Do not call on mobile.
void saveImageToDownloads(List<int> bytes, String filename) {
  throw UnsupportedError('saveImageToDownloads is only supported on web');
}
