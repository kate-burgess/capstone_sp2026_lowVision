import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_colors.dart';
import 'ocr_config.dart';
import 'translated_text.dart';

class DisplayPictureScreen extends StatelessWidget {
  const DisplayPictureScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  static Future<void> push(BuildContext context, Uint8List imageBytes) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DisplayPictureScreen(imageBytes: imageBytes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DisplayPictureBody(imageBytes: imageBytes);
  }
}

class _DisplayPictureBody extends StatefulWidget {
  const _DisplayPictureBody({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_DisplayPictureBody> createState() => _DisplayPictureBodyState();
}

class _DisplayPictureBodyState extends State<_DisplayPictureBody> {
  bool _isProcessing = false;
  String _extractedText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _performOCR();
  }

  Future<void> _performOCR() async {
    setState(() {
      _isProcessing = true;
      _extractedText = '';
      _error = null;
    });

    try {
      final request = http.MultipartRequest('POST', ocrMultipartUri());
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          widget.imageBytes,
          filename: 'image.png',
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        setState(() {
          _extractedText =
              (data['full_text'] as String?) ?? 'No text found';
        });
      } else {
        setState(() {
          _error = 'OCR server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error =
            'Could not reach the OCR service. For local dev, run ocr_server.py; '
            'for MAGIC, build with --dart-define=OCR_BASE_URL=<your-server>.\n\nDetails: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Tx('Photo & Extracted Text'),
        actions: [
          IconButton(
            tooltip: 'Re-run OCR',
            onPressed: _isProcessing ? null : _performOCR,
            icon: const Icon(Icons.refresh, size: 28),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              color: const Color(0xFF1A1D24),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tx('Extracted Text',
                          style: theme.textTheme.headlineMedium),
                      const SizedBox(width: 10),
                      if (_isProcessing)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Color(0xFF6D5EF5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kBrandCanvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12, width: 1),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _error ??
                              (_extractedText.isEmpty
                                  ? (_isProcessing
                                      ? 'Processing image...'
                                      : 'No text found')
                                  : _extractedText),
                          style: TextStyle(
                            color: _error != null
                                ? theme.colorScheme.error
                                : const Color(0xFF6D5EF5),
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Tx(
                      kIsWeb ? 'Pick Another Image' : 'Take Another Picture',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
