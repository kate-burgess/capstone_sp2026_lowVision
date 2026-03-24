import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'ocr_config.dart';
import 'take_picture_screen.dart';

class _Item {
  final String id;
  final String name;
  final String category;
  bool isChecked;
  int? aisle;

  _Item({
    required this.id,
    required this.name,
    required this.category,
    required this.isChecked,
    this.aisle,
  });

  static _Item fromMap(Map<String, dynamic> m) => _Item(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'Other',
        isChecked: m['is_checked'] as bool? ?? false,
      );
}

enum _Phase { aisleSign, aisleResults, shelf, shelfResults }

class AisleScannerScreen extends StatefulWidget {
  final String listId;
  final String listTitle;
  final List<Map<String, dynamic>> items;

  const AisleScannerScreen({
    super.key,
    required this.listId,
    required this.listTitle,
    required this.items,
  });

  @override
  State<AisleScannerScreen> createState() => _AisleScannerScreenState();
}

class _AisleScannerScreenState extends State<AisleScannerScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _takingPicture = false;
  String? _cameraError;
  int _cameraIndex = 0;

  final FlutterTts _tts = FlutterTts();
  bool _audioEnabled = true;

  _Phase _phase = _Phase.aisleSign;
  int _currentAisle = 1;
  bool _ocrLoading = false;
  String? _ocrError;
  String _aisleOcrText = '';
  String _shelfOcrText = '';
  List<_Item> _aisleMatches = [];
  List<_Item> _shelfMatches = [];

  late List<_Item> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map(_Item.fromMap).toList();
    _tts.awaitSpeakCompletion(true);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak(
          'Shopping mode started for ${widget.listTitle}. '
          'Point your camera at the aisle sign and tap Scan Aisle Sign.',
        ));
  }

  @override
  void dispose() {
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) {
      setState(() => _cameraError = 'No camera found.');
      return;
    }
    final ctrl = CameraController(
      cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _restartCamera() async {
    _camera?.dispose();
    _camera = null;
    _cameraReady = false;
    await _initCamera();
  }

  Future<void> _flipCamera() async {
    if (cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    await _restartCamera();
  }

  final ImagePicker _picker = ImagePicker();

  Future<Uint8List?> _capturePhoto() async {
    if (_camera == null || !_cameraReady || _takingPicture) return null;
    setState(() => _takingPicture = true);
    try {
      final xFile = await _camera!.takePicture();
      return await xFile.readAsBytes();
    } catch (e) {
      setState(() => _ocrError = 'Camera error: $e');
      return null;
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<Uint8List?> _pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return null;
    return await xFile.readAsBytes();
  }

  Future<void> _uploadToMagic(Uint8List bytes, String filename) async {
    try {
      final req = http.MultipartRequest('POST', uploadUri())
        ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: filename));
      await req.send();
    } catch (_) {
      // Upload is best-effort; don't block OCR if it fails.
    }
  }

  Future<String?> _runOcr(Uint8List bytes) async {
    setState(() {
      _ocrLoading = true;
      _ocrError = null;
    });
    try {
      final req = http.MultipartRequest('POST', ocrMultipartUri())
        ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'));
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        return (data['full_text'] as String?)?.trim() ?? '';
      }
      setState(() => _ocrError = 'OCR server error ${res.statusCode}.');
      return null;
    } catch (_) {
      setState(() => _ocrError =
          'Cannot reach OCR service. For local dev run ocr_server.py; for MAGIC use --dart-define=OCR_BASE_URL=<url>.');
      return null;
    } finally {
      if (mounted) setState(() => _ocrLoading = false);
    }
  }

  List<_Item> _matchItems(String ocrText) {
    final lower = ocrText.toLowerCase();
    return _items.where((item) {
      if (item.isChecked) return false;
      final nw = item.name.toLowerCase().split(RegExp(r'\s+'));
      final cw = item.category.toLowerCase().split(RegExp(r'[\s&]+'));
      return nw.any((w) => w.length > 2 && lower.contains(w)) ||
          cw.any((w) => w.length > 2 && lower.contains(w));
    }).toList();
  }

  Future<void> _onScanAisleSign({bool fromGallery = false}) async {
    final Uint8List? bytes;
    if (fromGallery) {
      bytes = await _pickFromGallery();
    } else {
      await _speak('Taking photo. Hold still.');
      bytes = await _capturePhoto();
    }
    if (bytes == null) return;
    await _speak('Reading aisle sign.');
    final text = await _runOcr(bytes);
    if (text == null) {
      await _speak('Could not read the sign. Please try again.');
      return;
    }
    _aisleOcrText = text;
    _aisleMatches = _matchItems(text);
    for (final item in _aisleMatches) {
      item.aisle ??= _currentAisle;
    }
    setState(() => _phase = _Phase.aisleResults);
    if (_aisleMatches.isEmpty) {
      await _speak(
          'Aisle $_currentAisle scanned. No list items match this aisle. '
          'You can scan the shelf or move to the next aisle.');
    } else {
      final names = _aisleMatches.map((i) => i.name).join(', ');
      await _speak('Aisle $_currentAisle. '
          '${_aisleMatches.length} item${_aisleMatches.length == 1 ? "" : "s"} here: $names.');
    }
  }

  Future<void> _onGoToShelf() async {
    setState(() {
      _phase = _Phase.shelf;
      _shelfOcrText = '';
      _shelfMatches = [];
    });
    await _restartCamera();
    await _speak('Point your camera at the shelf and tap Scan Shelf.');
  }

  Future<void> _onScanShelf({bool fromGallery = false}) async {
    final Uint8List? bytes;
    if (fromGallery) {
      bytes = await _pickFromGallery();
    } else {
      await _speak('Taking photo. Hold still.');
      bytes = await _capturePhoto();
    }
    if (bytes == null) return;
    await _speak('Saving shelf image.');

    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final filename = 'shelf_$timestamp.png';

    try {
      await _uploadToMagic(bytes, filename);
      await _speak('Shelf image saved.');
    } catch (_) {
      await _speak('Could not save the image. Please try again.');
    }

    setState(() => _phase = _Phase.shelfResults);
  }

  Future<void> _onScanAnotherShelf() async {
    setState(() {
      _phase = _Phase.shelf;
      _shelfOcrText = '';
      _shelfMatches = [];
    });
    await _restartCamera();
    await _speak('Point at the next shelf and tap Scan Shelf.');
  }

  Future<void> _onNextAisle() async {
    setState(() {
      _currentAisle++;
      _phase = _Phase.aisleSign;
      _aisleOcrText = '';
      _shelfOcrText = '';
      _aisleMatches = [];
      _shelfMatches = [];
    });
    await _restartCamera();
    await _speak(
        'Moving to aisle $_currentAisle. Point at the aisle sign and tap Scan Aisle Sign.');
  }

  Future<void> _toggleItem(_Item item) async {
    setState(() => item.isChecked = !item.isChecked);
    await _speak(item.isChecked
        ? '${item.name} checked off.'
        : '${item.name} unchecked.');
  }

  Future<void> _speak(String text) async {
    if (!_audioEnabled || !mounted) return;
    await _tts.speak(text);
  }

  List<_Item> get _uncheckedSorted {
    final withAisle = _items
        .where((i) => !i.isChecked && i.aisle != null)
        .toList()
      ..sort((a, b) => a.aisle!.compareTo(b.aisle!));
    final noAisle = _items.where((i) => !i.isChecked && i.aisle == null).toList();
    return [...withAisle, ...noAisle];
  }

  @override
  Widget build(BuildContext context) {
    String title = _phase == _Phase.aisleSign
        ? 'Aisle $_currentAisle — Scan Sign'
        : _phase == _Phase.shelf
            ? 'Aisle $_currentAisle — Scan Shelf'
            : 'Aisle $_currentAisle';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: _audioEnabled ? 'Mute audio' : 'Unmute audio',
            icon: Icon(_audioEnabled ? Icons.volume_up : Icons.volume_off,
                size: 28),
            onPressed: () {
              setState(() => _audioEnabled = !_audioEnabled);
              if (!_audioEnabled) _tts.stop();
            },
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'View full list',
              icon: const Icon(Icons.list_alt),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildListDrawer(),
      body: _phase == _Phase.aisleSign || _phase == _Phase.shelf
          ? _buildCameraView()
          : _phase == _Phase.aisleResults
              ? _buildAisleResults()
              : _buildShelfResults(),
    );
  }

  Widget _buildCameraView() {
    final isAisle = _phase == _Phase.aisleSign;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraError != null)
                Center(
                    child: Text(_cameraError!,
                        style: const TextStyle(color: Colors.red)))
              else if (!_cameraReady)
                const Center(child: CircularProgressIndicator())
              else
                CameraPreview(_camera!),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Text(
                    isAisle
                        ? 'Point at the aisle sign\nthen tap the button below'
                        : 'Point at the shelf\nthen tap the button below',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),
              Positioned(
                  top: 70,
                  right: 12,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      iconSize: 28,
                      padding: const EdgeInsets.all(12),
                      tooltip: 'Switch camera',
                      onPressed: _flipCamera,
                      icon: const Icon(Icons.cameraswitch,
                          color: Colors.white),
                    ),
                  ),
                ),
              if (!isAisle && _aisleMatches.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.all(10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _aisleMatches
                          .where((i) => !i.isChecked)
                          .map((i) => Chip(
                                label: Text(i.name,
                                    style: const TextStyle(
                                        color: Colors.black, fontSize: 16)),
                                backgroundColor:
                                    const Color(0xFF00E5FF).withOpacity(0.9),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              if (_ocrLoading)
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: Color(0xFF00E5FF), strokeWidth: 4),
                        SizedBox(height: 16),
                        Text('Reading text...',
                            style:
                                TextStyle(color: Colors.white, fontSize: 22)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_ocrError != null)
          Container(
            color: const Color(0xFFFF6E6E).withOpacity(0.2),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFFF6E6E), size: 24),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_ocrError!,
                        style: const TextStyle(
                            color: Color(0xFFFF6E6E), fontSize: 18))),
              ],
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_takingPicture || _ocrLoading || !_cameraReady)
                        ? null
                        : (isAisle
                            ? () => _onScanAisleSign()
                            : () => _onScanShelf()),
                    icon: _takingPicture
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt),
                    label: Text(isAisle ? 'Scan Aisle Sign' : 'Scan Shelf',
                        style: const TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: (_takingPicture || _ocrLoading)
                      ? null
                      : (isAisle
                          ? () => _onScanAisleSign(fromGallery: true)
                          : () => _onScanShelf(fromGallery: true)),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAisleResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF00E5FF).withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.article_outlined,
                  color: Color(0xFF00E5FF), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _aisleOcrText.isEmpty ? '(no text detected)' : _aisleOcrText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, color: Color(0xFF00E5FF)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(
            _aisleMatches.isEmpty
                ? 'No list items match this aisle'
                : '${_aisleMatches.length} item${_aisleMatches.length == 1 ? "" : "s"} in aisle $_currentAisle:',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
          ),
        ),
        if (_aisleMatches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
                'No items matched. You can still scan the shelf or go to the next aisle.',
                style: TextStyle(color: Colors.white60, fontSize: 18)),
          ),
        Expanded(
          child: ListView(
            children: _aisleMatches
                .map((item) => CheckboxListTile(
                      value: item.isChecked,
                      onChanged: (_) => _toggleItem(item),
                      title: Text(item.name),
                      subtitle: Text(item.category,
                          style: const TextStyle(fontSize: 12)),
                      controlAffinity: ListTileControlAffinity.leading,
                    ))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onNextAisle,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Next Aisle'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _onGoToShelf,
                    icon: const Icon(Icons.view_agenda_outlined),
                    label: const Text('Scan Shelf'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShelfResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFD54F).withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.document_scanner_outlined,
                  color: Color(0xFFFFD54F), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _shelfOcrText.isEmpty
                      ? 'Shelf image saved'
                      : _shelfOcrText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, color: Color(0xFFFFD54F)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(
            _shelfMatches.isEmpty
                ? 'Shelf image saved to server'
                : '${_shelfMatches.length} item${_shelfMatches.length == 1 ? "" : "s"} found:',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
          ),
        ),
        if (_shelfMatches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
                'Try scanning another shelf in this aisle, or move to the next aisle.',
                style: TextStyle(color: Colors.white60, fontSize: 18)),
          ),
        Expanded(
          child: ListView(
            children: _shelfMatches
                .map((item) => CheckboxListTile(
                      value: item.isChecked,
                      onChanged: (_) => _toggleItem(item),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          decoration: item.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.isChecked ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text(item.category,
                          style: const TextStyle(fontSize: 12)),
                      secondary: Icon(
                        item.isChecked
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: item.isChecked ? Colors.green : null,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onScanAnotherShelf,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Another Shelf'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _onNextAisle,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Next Aisle'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListDrawer() {
    final unchecked = _uncheckedSorted;
    final checked = _items.where((i) => i.isChecked).toList();
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DrawerHeader(
            decoration:
                const BoxDecoration(color: Color(0xFF1E1E2C)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(widget.listTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${checked.length} of ${_items.length} checked',
                    style: const TextStyle(
                        color: Color(0xFF00E5FF), fontSize: 18)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Text('REMAINING',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00E5FF).withOpacity(0.7),
                    letterSpacing: 1.2)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...unchecked.map((item) => ListTile(
                      leading: item.aisle != null
                          ? CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF00E5FF),
                              child: Text('${item.aisle}',
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.black,
                                      fontWeight: FontWeight.bold)))
                          : const CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.white24,
                              child: Text('?',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16))),
                      title: Text(item.name,
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white)),
                      subtitle: Text(item.category,
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white60)),
                      trailing: Checkbox(
                          value: item.isChecked,
                          onChanged: (_) => _toggleItem(item)),
                    )),
                if (checked.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                    child: Text('CHECKED OFF',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.4),
                            letterSpacing: 1.2)),
                  ),
                  ...checked.map((item) => ListTile(
                        leading: const Icon(Icons.check_circle,
                            color: Color(0xFF00E5FF), size: 24),
                        title: Text(item.name,
                            style: const TextStyle(
                                fontSize: 20,
                                decoration: TextDecoration.lineThrough,
                                color: Colors.white38)),
                        trailing: Checkbox(
                            value: item.isChecked,
                            onChanged: (_) => _toggleItem(item)),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
