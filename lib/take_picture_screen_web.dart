import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'display_picture_screen.dart';
import 'save_image_stub.dart' if (dart.library.html) 'save_image_web.dart';

/// Web: pick a file (or capture if supported), save to Downloads, then show OCR result.

Future<void> initCameras() async {}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key});

  @override
  State<TakePictureScreen> createState() => _TakePictureScreenState();
}

class _TakePictureScreenState extends State<TakePictureScreen> {
  bool _isLoading = false;

  Future<void> _pickAndProcess() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (xFile == null || !mounted) return;

      final bytes = await xFile.readAsBytes();
      if (bytes.isEmpty || !mounted) return;

      // Save image to computer's Downloads folder (browser download)
      final name = xFile.name.isNotEmpty ? xFile.name : 'ocr_image.png';
      saveImageToDownloads(bytes, name);

      if (!mounted) return;
      await DisplayPictureScreen.push(context, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick image for OCR')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Choose an image to save to Downloads and extract text.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickAndProcess,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library),
              label: Text(_isLoading ? 'Processing...' : 'Pick image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
