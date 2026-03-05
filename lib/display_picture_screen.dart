import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  String get _ocrBaseUrl =>
      kIsWeb ? 'http://localhost:5000' : 'http://10.0.2.2:5000';

  Future<void> _performOCR() async {
    setState(() {
      _isProcessing = true;
      _extractedText = '';
      _error = null;
    });

    try {
      final uri = Uri.parse('$_ocrBaseUrl/extract-text');
      final request = http.MultipartRequest('POST', uri);
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
            'Could not connect to OCR server. Make sure ocr_server.py is running.\n\nDetails: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo & Extracted Text'),
        actions: [
          IconButton(
            onPressed: _isProcessing ? null : _performOCR,
            icon: const Icon(Icons.refresh),
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
              color: Colors.grey[900],
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Extracted Text',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isProcessing)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
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
                                ? Colors.red[300]
                                : Colors.green[300],
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(
                        kIsWeb ? 'Pick another image' : 'Take Another Picture',
                      ),
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
