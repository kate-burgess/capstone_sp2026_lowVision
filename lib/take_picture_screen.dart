import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


import 'display_picture_screen.dart';
import 'ocr_config.dart';
import 'save_image_stub.dart' if (dart.library.html) 'save_image_web.dart';

late List<CameraDescription> cameras;

Future<void> initCameras() async {
  cameras = await availableCameras();
}

/// Single camera screen for both web and mobile: live camera preview + capture button.
/// On web this uses camera_web for the preview; no file picker.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key});

  @override
  State<TakePictureScreen> createState() => _TakePictureScreenState();
}

class _TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isTakingPicture = false;
  String? _error;
  final ImagePicker _picker = ImagePicker();
  String detectedLabel = "No object yet";


  @override
  void initState() {
    super.initState();
    if (cameras.isEmpty) {
      _error = 'No camera found. Allow camera access and refresh.';
      return;
    }
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    if (cameras.isNotEmpty) {
      _controller.dispose();
    }
    super.dispose();
  }

Future<void> _takePicture() async {
  if (_isTakingPicture || _error != null) return;
  setState(() => _isTakingPicture = true);

  try {
    await _initializeControllerFuture;

    final xFile = await _controller.takePicture();
    final bytes = await xFile.readAsBytes();

    if (bytes.isEmpty || !mounted) return;

    print("Picture taken");

    // Save on web (your existing logic)
    if (kIsWeb) {
      final name = xFile.name.isNotEmpty ? xFile.name : _defaultPhotoName();
      saveImageToDownloads(bytes, name);
    }

    // 🔥 SEND TO SERVER
    var request = http.MultipartRequest(
      "POST",
      yoloDetectUri(),
    );

    request.files.add(
      kIsWeb
          ? http.MultipartFile.fromBytes(
              "image",
              bytes,
              filename: xFile.name.isNotEmpty ? xFile.name : "upload.jpg",
            )
          : await http.MultipartFile.fromPath(
              "image",
              xFile.path,
            ),
    );

    print("Sending request...");

    var response = await request.send();

    print("Response received");

    var responseData = await response.stream.bytesToString();
    var decoded = jsonDecode(responseData);

    if (!mounted) return;

    if (decoded.isNotEmpty) {
      final labels = decoded.map((obj) {
        final raw = '${obj["label"]}'.trim();
        final lower = raw.toLowerCase();
        if (lower == 'none' || lower == 'none.') {
          return 'no item detected.';
        }
        return raw;
      }).toList();

      setState(() {
        detectedLabel = labels.join(", ");
      });
    } else {
      setState(() {
        detectedLabel = "No object detected";
      });
    }

    // Show image after processing
    await DisplayPictureScreen.push(context, bytes);

  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isTakingPicture = false);
  }
}

  Future<void> _pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (bytes.isEmpty || !mounted) return;

    if (kIsWeb) {
      final name = xFile.name.isNotEmpty ? xFile.name : _defaultPhotoName();
      saveImageToDownloads(bytes, name);
    }

    if (!mounted) return;
    await DisplayPictureScreen.push(context, bytes);
  }

  String _defaultPhotoName() {
    final now = DateTime.now();
    return 'ocr_photo_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.png';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => initCameras().then((_) => setState(() {})),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Camera error: ${snapshot.error}',
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => setState(() {
                              _initializeControllerFuture =
                                  _controller.initialize();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return CameraPreview(_controller);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Point at text, then tap to capture',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
          ),

          Positioned(
                top: 60,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    detectedLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            label: 'Pick image from gallery',
            child: FloatingActionButton(
              heroTag: 'gallery',
              onPressed: _pickFromGallery,
              child: const Icon(Icons.photo_library, size: 30),
            ),
          ),
          const SizedBox(width: 28),
          Semantics(
            label: 'Take photo',
            child: FloatingActionButton.large(
              heroTag: 'camera',
              onPressed: _takePicture,
              child: _isTakingPicture
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.black),
                    )
                  : const Icon(Icons.camera_alt, size: 40),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
