// Web-only: trigger browser download so the image saves to the user's Downloads folder.
import 'dart:html' as html;
import 'dart:typed_data';

void saveImageToDownloads(List<int> bytes, String filename) {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
