import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'grocery_list_detail_screen.dart';
import 'main.dart';
import 'ocr_config.dart';

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

const _kMenuEnd = 'end';
const _kMenuAisle = 'aisle';
const _kMenuMute = 'mute';
const _kMenuList = 'list';

const _shoppingMenuOrderDefault = [
  _kMenuEnd,
  _kMenuAisle,
  _kMenuMute,
  _kMenuList,
];

const _prefsVlmMenuOrder = 'vlm_shopping_menu_order_v1';

class AisleScannerVlmScreen extends StatefulWidget {
  final String listId;
  final String listTitle;
  final List<Map<String, dynamic>> items;
  final List<CameraDescription> cameras;

  const AisleScannerVlmScreen({
    super.key,
    required this.listId,
    required this.listTitle,
    required this.items,
    required this.cameras,
  });

  @override
  State<AisleScannerVlmScreen> createState() => _AisleScannerVlmScreenState();
}

class _AisleScannerVlmScreenState extends State<AisleScannerVlmScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _takingPicture = false;
  String? _cameraError;
  int _cameraIndex = 0;

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  bool _speechAvailable = false;
  Completer<void>? _stopAisleListenRequested;

  _Phase _phase = _Phase.aisleSign;
  int _currentAisle = 1;
  String _currentAisleLabel = '1';

  bool _loading = false;
  String? _error;

  String _aisleOcrText = '';
  String _aisleStatusMessage = '';
  String _shelfOcrText = '';
  String _shelfStatusMessage = '';
  String _vlmAnswer = '';
  String _lastSpoken = '';
  bool _audioEnabled = true;
  bool _shoppingMenuOpen = false;
  bool _fullScreenListOpen = false;
  bool _showAisleUnclearEmployeeOption = false;
  List<String> _menuOrder = List<String>.from(_shoppingMenuOrderDefault);

  List<_Item> _aisleMatches = [];
  List<_Item> _shelfMatches = [];
  List<_Item> _pendingShelfItems = [];
  int _shelfPromptIndex = 0;

  late List<_Item> _items;
  late Map<String, bool> _initialCheckedById;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map(_Item.fromMap).toList();
    _initialCheckedById = {for (final item in _items) item.id: item.isChecked};
    _tts.awaitSpeakCompletion(true);
    _initSpeech();
    _initCamera();
    _loadMenuOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak(
        'VLM shopping mode started for ${widget.listTitle}. Point your camera at the aisle sign and tap Scan Aisle Sign.',
      );
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (err) {
          if (!mounted) return;
          final msg = err.errorMsg;
          if (msg.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Speech recognition: $msg',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            );
          }
        },
        onStatus: (_) {},
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  /// Listens for an aisle name. Uses [ListenMode.dictation] (not the default
  /// short-phrase mode). On web, finals often arrive only after [stop], so we
  /// always [stop] and take the latest partial text. [onPartial] updates UI.
  Future<String> _listenForSpokenAislePhrase({
    void Function(String partial)? onPartial,
  }) async {
    if (!_speechAvailable) return '';

    await _tts.stop();
    await Future<void>.delayed(const Duration(milliseconds: 600));

    var recognized = '';
    final done = Completer<void>();
    final stopRequested = Completer<void>();
    _stopAisleListenRequested = stopRequested;

    void maybeFinish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      if (_speech.isListening) {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      await _speech.listen(
        onResult: (result) {
          recognized = result.recognizedWords;
          if (recognized.isNotEmpty) {
            onPartial?.call(recognized);
          }
          if (result.finalResult) {
            maybeFinish();
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );

      await Future.any<void>([
        done.future,
        stopRequested.future,
      ]).timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    } finally {
      _stopAisleListenRequested = null;
      if (_speech.isListening) {
        await _speech.stop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    return recognized.trim();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _cameraError = 'No camera found.');
      return;
    }

    final ctrl = CameraController(
      widget.cameras[_cameraIndex],
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
    await _camera?.dispose();
    _camera = null;
    _cameraReady = false;
    await _initCamera();
  }

  Future<void> _flipCamera() async {
    if (widget.cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
    await _restartCamera();
  }

  Future<Uint8List?> _capturePhoto() async {
    if (_camera == null || !_cameraReady || _takingPicture) return null;
    setState(() => _takingPicture = true);
    try {
      final xFile = await _camera!.takePicture();
      return await xFile.readAsBytes();
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
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

  Future<String?> _runOcr(Uint8List bytes) async {
    try {
      final req = http.MultipartRequest('POST', ocrMultipartUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'),
        );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        return (data['full_text'] as String?)?.trim() ?? '';
      }

      setState(() => _error = 'OCR server error ${res.statusCode}.');
      return null;
    } catch (_) {
      setState(() => _error =
          'Cannot reach OCR service at ${ocrServiceBaseUrl()}.');
      return null;
    }
  }

  Future<String> _runVlmPredict(
    Uint8List bytes, {
    required String question,
  }) async {
    try {
      final req = http.MultipartRequest('POST', vlmPredictUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'),
        )
        ..fields['question'] = question;

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode != 200) {
        // Surface server errors instead of swallowing them.
        try {
          final decoded = json.decode(body);
          if (decoded is Map<String, dynamic> && decoded['error'] is String) {
            return 'VLM server error ${res.statusCode}: ${decoded['error']}';
          }
        } catch (_) {}
        final snippet = body.trim();
        return snippet.isEmpty
            ? 'VLM server error ${res.statusCode}.'
            : 'VLM server error ${res.statusCode}: $snippet';
      }

      final decoded = json.decode(body) as Map<String, dynamic>;
      final answer = (decoded['answer'] as String? ?? '').trim();
      return answer.isEmpty ? 'VLM returned an empty answer.' : answer;
    } catch (e) {
      return 'VLM request failed: $e';
    }
  }

  bool _vlmSaysItemFound(String answer) {
    final upper = answer.toUpperCase();
    // Important: "ITEM NOT FOUND" contains the substring "ITEM FOUND".
    if (upper.contains('ITEM NOT FOUND')) return false;
    return RegExp(r'\bITEM FOUND\b').hasMatch(upper);
  }

  bool _vlmAnswerMatchesTarget(String answer, _Item target) {
    final answerWords = _tokenize(answer);
    final targetWords = _tokenize(target.name);
    for (final t in targetWords) {
      if (answerWords.any((w) => _isFuzzyTokenMatch(t, w))) return true;
    }
    return false;
  }

  String _normalizeToken(String token) {
    final lower = token.toLowerCase();
    final normalized = lower
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll(r'$', 's');

    if (normalized.length > 3 && normalized.endsWith('s')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Set<String> _tokenize(String text) {
    return text
        .split(RegExp(r'[^A-Za-z0-9$]+'))
        .map(_normalizeToken)
        .where((w) => w.length > 2)
        .toSet();
  }

  bool _looksLikeUsefulAisleText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    if (letterCount < 3) return false;
    final tokens = _tokenize(trimmed);
    return tokens.isNotEmpty;
  }

  int _levenshteinDistance(String a, String b, {int maxDistance = 2}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      int minInRow = curr[0];
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (curr[j] < minInRow) minInRow = curr[j];
      }
      if (minInRow > maxDistance) return maxDistance + 1;
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[b.length];
  }

  bool _isFuzzyTokenMatch(String target, String candidate) {
    if (target == candidate) return true;
    if (target[0] != candidate[0]) return false;
    final maxDistance = target.length >= 10 || candidate.length >= 10 ? 2 : 1;
    return _levenshteinDistance(target, candidate, maxDistance: maxDistance) <=
        maxDistance;
  }

  bool _itemMatchesText(_Item item, Set<String> words) {
    final itemWords = {..._tokenize(item.name), ..._tokenize(item.category)};
    for (final target in itemWords) {
      if (words.any((word) => _isFuzzyTokenMatch(target, word))) {
        return true;
      }
    }
    return false;
  }

  List<_Item> _matchItems(String text) {
    final words = _tokenize(text);
    return _items.where((item) {
      if (item.isChecked) return false;
      return _itemMatchesText(item, words);
    }).toList();
  }

  _Item? get _currentShelfTarget {
    if (_pendingShelfItems.isEmpty) return null;
    if (_shelfPromptIndex < 0 || _shelfPromptIndex >= _pendingShelfItems.length) {
      return null;
    }
    return _pendingShelfItems[_shelfPromptIndex];
  }

  Future<void> _onScanAisleSign({bool fromGallery = false}) async {
    final Uint8List? bytes =
        fromGallery ? await _pickFromGallery() : await _capturePhoto();
    if (bytes == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _showAisleUnclearEmployeeOption = false;
    });

    await _speak('Reading aisle sign.');

    final text = await _runOcr(bytes);

    setState(() => _loading = false);

    if (text == null) {
      setState(() => _showAisleUnclearEmployeeOption = true);
      await _speak(
        'Could not read the sign. You can try again, or tap Get Help from store employee.',
      );
      return;
    }

    _aisleOcrText = text;

    if (!_looksLikeUsefulAisleText(text)) {
      setState(() {
        _phase = _Phase.aisleSign;
        _aisleStatusMessage = 'Sign text unclear. Retake photo or get employee help.';
        _showAisleUnclearEmployeeOption = true;
      });
      await _speak(
        'This aisle sign is unclear. Try a closer photo, or tap Get Help from store employee.',
      );
      return;
    }

    setState(() => _showAisleUnclearEmployeeOption = false);

    _aisleMatches = _matchItems(text);
    _pendingShelfItems = _aisleMatches.where((i) => !i.isChecked).toList();
    _shelfPromptIndex = 0;

    for (final item in _aisleMatches) {
      item.aisle ??= _currentAisle;
    }

    setState(() {
      _phase = _Phase.aisleResults;
      _aisleStatusMessage = _aisleMatches.isEmpty
          ? 'No list items match this aisle.'
          : 'Matched items: ${_aisleMatches.map((e) => e.name).join(", ")}';
    });

    await _speak(_aisleStatusMessage);
  }

  Future<void> _onGoToShelf() async {
    setState(() {
      _phase = _Phase.shelf;
      _shelfStatusMessage = '';
      _shelfOcrText = '';
      _vlmAnswer = '';
      _shelfMatches = [];
    });

    await _restartCamera();

    final target = _currentShelfTarget;
    if (target != null) {
      await _speak(
        'Point your camera at the shelf for ${target.name}, then tap Scan Shelf.',
      );
    } else {
      await _speak('Point your camera at the shelf, then tap Scan Shelf.');
    }
  }

  Future<void> _onScanShelf({bool fromGallery = false}) async {
    final Uint8List? bytes =
        fromGallery ? await _pickFromGallery() : await _capturePhoto();
    if (bytes == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    await _speak('Reading shelf.');

    final shelfText = await _runOcr(bytes);
    final target = _currentShelfTarget;

    String question;
    if (target != null) {
      question =
          'Do NOT read any text, labels, or signs. Use only visual appearance. '
          'First, describe what grocery item you see concisely (1–2 sentences). '
          'Then, say whether the described item matches "${target.name}". '
          'If it matches, end with: ITEM FOUND.';
    } else {
      question =
          'Do NOT read any text, labels, or signs. Use only visual appearance. '
          'Describe the main grocery item(s) you see concisely for a low-vision user.';
    }

    final vlmAnswer = await _runVlmPredict(bytes, question: question);

    setState(() => _loading = false);

    if (shelfText == null) {
      await _speak('Could not read the shelf text. Please try again.');
      return;
    }

    _shelfOcrText = shelfText;
    _vlmAnswer = vlmAnswer;
    _shelfMatches = _matchItems(shelfText);

    final matchedNames = _shelfMatches.map((i) => i.name).join(', ');
    // "Found" must not rely on ITEM FOUND alone—the model can say that for the
    // wrong product (e.g. target diapers, image peppers). Require the answer to
    // actually mention the target, and if shelf OCR matches a *different* list
    // item but not the target, treat as not found unless OCR also matches target.
    final vlmSaysFound = _vlmSaysItemFound(vlmAnswer);
    final answerNamesTarget =
        target != null && _vlmAnswerMatchesTarget(vlmAnswer, target);
    final targetOnShelfByOcr =
        target != null && _itemMatchesText(target, _tokenize(shelfText));
    final shelfMatchesOtherListItem = target != null &&
        _shelfMatches.any((i) => !identical(i, target));

    final targetFound = target != null &&
        vlmSaysFound &&
        answerNamesTarget &&
        (targetOnShelfByOcr || !shelfMatchesOtherListItem);

    setState(() {
      if (matchedNames.isEmpty) {
        _shelfStatusMessage = vlmAnswer.isEmpty
            ? 'VLM detected: nothing clear.'
            : 'VLM detected: $vlmAnswer';
      } else {
        _shelfStatusMessage = vlmAnswer.isEmpty
            ? 'Detected list matches: $matchedNames'
            : 'Detected list matches: $matchedNames. VLM detected: $vlmAnswer';
      }
      _phase = _Phase.shelfResults;
    });

    await _speak(_shelfStatusMessage);

    if (target != null) {
      if (!mounted) return;
      final wantCheck = await _showCheckOffItemDialog(
        found: targetFound,
        itemName: target.name,
      );
      if (!mounted) return;
      if (wantCheck == true) {
        setState(() => target.isChecked = true);
        await _saveItemCheckedState(target);
        await _speak('${target.name} checked off.');
      } else if (wantCheck == false) {
        await _speak('Okay. ${target.name} is still on your list.');
      }
      if (targetFound) {
        await _speak('Go to the next aisle and scan.');
      } else {
        await _speak('Scan aisle again.');
      }
    }
  }

  /// Large “textbox” style tap targets for Yes / No (accessibility).
  Widget _checkOffAnswerBox({
    required String label,
    required VoidCallback onTap,
    required Color borderColor,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 3),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _showCheckOffItemDialog({
    required bool found,
    required String itemName,
  }) async {
    final spokenPrompt = found
        ? 'Item found. Do you want to check off item? Yes or no.'
        : 'Item not found. Do you want to check off item? Yes or no.';
    await _speak(spokenPrompt);
    if (!mounted) return null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          found ? 'Item found' : 'Item not found',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Looking for: $itemName',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text(
                'Do you want to check off this item?',
                style: TextStyle(fontSize: 24, height: 1.3),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _checkOffAnswerBox(
                      label: 'Yes',
                      borderColor: const Color(0xFF00E5FF),
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _checkOffAnswerBox(
                      label: 'No',
                      borderColor: const Color(0xFFFFD54F),
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onNextAisle() async {
    setState(() {
      _currentAisle++;
      _currentAisleLabel = _currentAisle.toString();
      _phase = _Phase.aisleSign;
      _aisleOcrText = '';
      _aisleStatusMessage = '';
      _shelfOcrText = '';
      _shelfStatusMessage = '';
      _vlmAnswer = '';
      _aisleMatches = [];
      _shelfMatches = [];
      _pendingShelfItems = [];
      _shelfPromptIndex = 0;
      _showAisleUnclearEmployeeOption = false;
    });

    await _restartCamera();
    await _speak(
      'Moving to aisle $_currentAisleLabel. Point at the aisle sign and tap Scan Aisle Sign.',
    );
  }

  Future<void> _toggleItem(_Item item) async {
    setState(() => item.isChecked = !item.isChecked);
    await _saveItemCheckedState(item);
    await _speak(
      item.isChecked ? '${item.name} checked off.' : '${item.name} unchecked.',
    );
  }

  Future<void> _reloadItemsFromServer() async {
    try {
      final rows = await supabase
          .from('grocery_items')
          .select()
          .eq('list_id', widget.listId)
          .order('name');
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _items = list.map(_Item.fromMap).toList();
        _initialCheckedById = {
          for (final item in _items) item.id: item.isChecked,
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh list: $e')),
      );
    }
  }

  Future<void> _openAddItemsFromDrawer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroceryListDetailScreen(
          listId: widget.listId,
          listTitle: widget.listTitle,
        ),
      ),
    );
    if (mounted) await _reloadItemsFromServer();
  }

  Future<void> _loadMenuOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsVlmMenuOrder);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      var parsed = decoded.map((e) => e.toString()).toList();
      parsed.removeWhere((k) => k == 'check');
      if (parsed.length != _shoppingMenuOrderDefault.length) return;
      if (parsed.toSet().length != _shoppingMenuOrderDefault.length) return;
      for (final k in parsed) {
        if (!_shoppingMenuOrderDefault.contains(k)) return;
      }
      if (mounted) setState(() => _menuOrder = parsed);
    } catch (_) {}
  }

  Future<void> _saveMenuOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsVlmMenuOrder, jsonEncode(_menuOrder));
    } catch (_) {}
  }

  void _scheduleCameraResumeIfInCameraPhase() {
    if (_phase != _Phase.aisleSign && _phase != _Phase.shelf) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _restartCamera();
    });
  }

  void _closeShoppingMenuWithCameraResume() {
    if (!_shoppingMenuOpen) return;
    setState(() => _shoppingMenuOpen = false);
    _scheduleCameraResumeIfInCameraPhase();
  }

  Future<void> _applyAisleValueFromString(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Type or say an aisle name (for example: dairy or bakery).',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
      return;
    }

    final aisleWords = _tokenize(value);
    final matches = _items.where((item) {
      if (item.isChecked) return false;
      return _itemMatchesText(item, aisleWords);
    }).toList();

    if (matches.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No list items match "$value". Try another aisle name.',
            style: const TextStyle(fontSize: 18),
          ),
        ),
      );
      await _speak('No list items match $value. Try another aisle name.');
      return;
    }

    setState(() {
      _currentAisleLabel = value;
      _phase = _Phase.aisleResults;
      _aisleOcrText = value;
      _aisleStatusMessage = '';
      _shelfOcrText = '';
      _aisleMatches = matches;
      _shelfMatches = [];
      _shelfStatusMessage = '';
      _pendingShelfItems = matches.where((i) => !i.isChecked).toList();
      _shelfPromptIndex = 0;
      _showAisleUnclearEmployeeOption = false;
    });
    for (final item in matches) {
      item.aisle ??= _currentAisle;
    }
    final names = matches.map((e) => e.name).join(', ');
    await _speak(
      'Aisle $_currentAisleLabel selected. You have $names to find. Open the menu for your full list.',
    );
  }

  Future<void> _showSpokenAisleSheet({required bool employeeMode}) async {
    if (!mounted) return;

    final typeController = TextEditingController();
    var transcript = '';
    var listening = false;

    String combinedValue() {
      final typed = typeController.text.trim();
      if (typed.isNotEmpty) return typed;
      return transcript.trim();
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) {
            final hasValue = combinedValue().isNotEmpty;
            return AlertDialog(
              title: Text(
                employeeMode
                    ? 'Store employee: aisle name'
                    : 'Aisle name',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (employeeMode) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF00E5FF),
                            width: 2,
                          ),
                        ),
                        child: const Text(
                          'FOR STORE EMPLOYEE\n\n'
                          'Please look at this screen. The shopper needs the '
                          'aisle location.\n\n'
                          'Type the aisle name below, or tap the microphone and '
                          'clearly say the aisle name you are in (for example: '
                          '"Bakery" or "Dairy"). That name will be set in the app.',
                          style: TextStyle(
                            fontSize: 22,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      const Text(
                        'Type the aisle name, or tap the microphone and say it '
                        '(for example: "dairy" or "bakery"). Names only—no aisle '
                        'numbers.',
                        style: TextStyle(fontSize: 22, height: 1.3),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: typeController,
                      style: const TextStyle(fontSize: 22),
                      decoration: const InputDecoration(
                        labelText: 'Type aisle name',
                        hintText: 'e.g. dairy, bakery, produce',
                        labelStyle: TextStyle(fontSize: 20),
                        hintStyle: TextStyle(fontSize: 18),
                      ),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setModal(() {}),
                    ),
                    const SizedBox(height: 20),
                    if (!_speechAvailable)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Speech is not available here—use the text box above.',
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                      ),
                    FilledButton.icon(
                      icon: Icon(
                        listening ? Icons.mic : Icons.mic_none,
                        size: 32,
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        textStyle: const TextStyle(fontSize: 22),
                      ),
                      onPressed: (!_speechAvailable || listening)
                          ? null
                          : () async {
                              setModal(() {
                                listening = true;
                                transcript = '';
                              });
                              await _speak(
                                employeeMode
                                    ? 'Employee, please say the aisle name now.'
                                    : 'Say the aisle name now.',
                              );
                              final heard = await _listenForSpokenAislePhrase(
                                onPartial: (w) {
                                  if (ctx.mounted) {
                                    setModal(() => transcript = w);
                                  }
                                },
                              );
                              if (ctx.mounted) {
                                setModal(() {
                                  listening = false;
                                  transcript = heard;
                                });
                              }
                            },
                      label: Text(
                        listening ? 'Listening…' : 'Tap microphone to speak',
                      ),
                    ),
                    if (listening) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final c = _stopAisleListenRequested;
                          if (c != null && !c.isCompleted) {
                            c.complete();
                          }
                          await _speech.stop();
                        },
                        child: const Text(
                          'Stop listening',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Allow the microphone if your browser asks. You should '
                        'see words appear as you speak. Tap Stop listening when '
                        'you are done.',
                        style: TextStyle(fontSize: 17, color: Colors.white60),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      transcript.isEmpty
                          ? 'Heard text will appear here.'
                          : 'Heard: $transcript',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: transcript.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w700,
                        color:
                            transcript.isEmpty ? Colors.white54 : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(fontSize: 20)),
                ),
                FilledButton(
                  onPressed: !hasValue
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _applyAisleValueFromString(combinedValue());
                        },
                  child:
                      const Text('Use this aisle', style: TextStyle(fontSize: 20)),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      final c = _stopAisleListenRequested;
      if (c != null && !c.isCompleted) {
        c.complete();
      }
      if (_speech.isListening) {
        await _speech.stop();
      }
      typeController.dispose();
    }
  }

  Future<void> _openSayAisleFromMenu() async {
    _closeShoppingMenuWithCameraResume();
    await _showSpokenAisleSheet(employeeMode: false);
  }

  void _openEmployeeAisleHelp() {
    _showSpokenAisleSheet(employeeMode: true);
  }

  void _openFullScreenListFromMenu() {
    setState(() {
      _shoppingMenuOpen = false;
      _fullScreenListOpen = true;
    });
  }

  void _closeFullScreenList() {
    setState(() => _fullScreenListOpen = false);
    _scheduleCameraResumeIfInCameraPhase();
  }

  Widget _largeMenuButton({
    required String label,
    required String semanticLabel,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: double.infinity,
        height: 88,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            textStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 36),
              const SizedBox(width: 20),
              Expanded(child: Text(label, maxLines: 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuActionBodyForId(String id) {
    switch (id) {
      case _kMenuEnd:
        return _largeMenuButton(
          label: 'End shopping',
          semanticLabel: 'End shopping and save progress',
          icon: Icons.stop_circle_outlined,
          onPressed: _loading
              ? null
              : () {
                  setState(() => _shoppingMenuOpen = false);
                  _onEndShopping();
                },
        );
      case _kMenuAisle:
        return _largeMenuButton(
          label: 'Set aisle name',
          semanticLabel: 'Type or speak the aisle name (no aisle numbers)',
          icon: Icons.mic,
          onPressed: _loading ? null : _openSayAisleFromMenu,
        );
      case _kMenuMute:
        return _largeMenuButton(
          label: _audioEnabled ? 'Mute audio' : 'Unmute audio',
          semanticLabel: _audioEnabled
              ? 'Mute spoken feedback'
              : 'Turn spoken feedback back on',
          icon: _audioEnabled ? Icons.volume_up : Icons.volume_off,
          onPressed: () {
            setState(() => _audioEnabled = !_audioEnabled);
            if (!_audioEnabled) _tts.stop();
          },
        );
      case _kMenuList:
        return _largeMenuButton(
          label: 'Shopping list & check off',
          semanticLabel:
              'Open full screen shopping list, check off items, and add items',
          icon: Icons.checklist,
          onPressed: _openFullScreenListFromMenu,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShoppingMenuRow(int index, String id) {
    return Card(
      key: ValueKey(id),
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _menuActionBodyForId(id)),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Drag to reorder this menu option',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, size: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessibilityShoppingMenu(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Shopping menu',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.listTitle,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use the grip icon on the right to drag options into any order. '
                'Your order is saved for next time.',
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
                  itemCount: _menuOrder.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final x = _menuOrder.removeAt(oldIndex);
                      _menuOrder.insert(newIndex, x);
                    });
                    _saveMenuOrder();
                  },
                  itemBuilder: (context, index) {
                    return _buildShoppingMenuRow(index, _menuOrder[index]);
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: OutlinedButton(
                  onPressed: _closeShoppingMenuWithCameraResume,
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Resume shopping'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveItemCheckedState(_Item item) async {
    if (item.id.isEmpty) return;
    try {
      await supabase
          .from('grocery_items')
          .update({'is_checked': item.isChecked})
          .eq('id', item.id)
          .eq('list_id', widget.listId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save "${item.name}".')),
      );
    }
  }

  Future<void> _saveAllProgress() async {
    for (final item in _items) {
      final initial = _initialCheckedById[item.id];
      if (initial != null && initial != item.isChecked) {
        await _saveItemCheckedState(item);
      }
    }
  }

  Future<void> _onEndShopping() async {
    setState(() => _loading = true);
    await _saveAllProgress();
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _speak(String text) async {
    if (mounted) {
      setState(() => _lastSpoken = text);
    } else {
      _lastSpoken = text;
    }
    if (!_audioEnabled || !mounted) return;
    await _tts.speak(text);
  }

  /// Colorful “Menu” control with explicit size so AppBar actions lay out on web
  /// (InputDecorator inside unbounded Ink caused layout / hit-test exceptions).
  Widget _shoppingMenuAppBarControl(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
      child: Tooltip(
        message: 'Open shopping menu',
        child: Semantics(
          button: true,
          label: 'Menu, open shopping menu',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _shoppingMenuOpen = true),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF00E5FF),
                      Color(0xFF26C6DA),
                      Color(0xFFFFD54F),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 42,
                    minWidth: 72,
                    maxWidth: 104,
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(
                        'Menu',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.3,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _phase == _Phase.aisleSign
        ? 'VLM Aisle $_currentAisleLabel — Scan Sign'
        : _phase == _Phase.shelf
            ? 'VLM Aisle $_currentAisleLabel — Scan Shelf'
            : 'VLM Aisle $_currentAisleLabel';

    return PopScope(
      canPop: !_shoppingMenuOpen && !_fullScreenListOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fullScreenListOpen) {
          _closeFullScreenList();
          return;
        }
        _closeShoppingMenuWithCameraResume();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _fullScreenListOpen
                ? 'Shopping list'
                : _shoppingMenuOpen
                    ? 'Menu'
                    : title,
          ),
          leading: _fullScreenListOpen
              ? IconButton(
                  tooltip: 'Close list',
                  icon: const Icon(Icons.close),
                  onPressed: _closeFullScreenList,
                )
              : _shoppingMenuOpen
                  ? IconButton(
                      tooltip: 'Close menu',
                      icon: const Icon(Icons.close),
                      onPressed: _closeShoppingMenuWithCameraResume,
                    )
                  : null,
          automaticallyImplyLeading:
              !_shoppingMenuOpen && !_fullScreenListOpen,
          actions: [
            if (!_shoppingMenuOpen && !_fullScreenListOpen)
              _shoppingMenuAppBarControl(context),
          ],
        ),
        body: _shoppingMenuOpen
            ? _buildAccessibilityShoppingMenu(context)
            : _fullScreenListOpen
                ? _buildFullScreenShoppingList()
                : _phase == _Phase.aisleSign || _phase == _Phase.shelf
                    ? _buildCameraView()
                    : _phase == _Phase.aisleResults
                        ? _buildAisleResults()
                        : _buildShelfResults(),
      ),
    );
  }

  Widget _buildFullScreenShoppingList() {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.listTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap items to check them off. Use Add items for more.',
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart, size: 28),
                  label: const Text(
                    'Add items',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _openAddItemsFromDrawer,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: _items
                      .map(
                        (item) => CheckboxListTile(
                          value: item.isChecked,
                          onChanged: (_) => _toggleItem(item),
                          title: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            item.category,
                            style: const TextStyle(fontSize: 20),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _closeFullScreenList,
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 22),
                  ),
                  child: const Text('Back to shopping'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    final isAisle = _phase == _Phase.aisleSign;
    final target = _currentShelfTarget;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraError != null)
                Center(child: Text(_cameraError!))
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
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isAisle
                        ? 'Point at the aisle sign'
                        : target != null
                            ? 'Point at shelf for ${target.name}'
                            : 'Point at the shelf',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),

              Positioned(
                top: 75,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _flipCamera,
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
                ),
              ),

              if (_loading)
                Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isAisle ? _onScanAisleSign : _onScanShelf,
                      child: Text(isAisle ? 'Scan Aisle Sign' : 'Scan Shelf'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => isAisle
                          ? _onScanAisleSign(fromGallery: true)
                          : _onScanShelf(fromGallery: true),
                      child: const Text('Use Gallery Image'),
                    ),
                  ),
                ],
              ),
              if (isAisle && _showAisleUnclearEmployeeOption) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _openEmployeeAisleHelp,
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Get Help from store employee'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAisleResults() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _aisleStatusMessage,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text(
            'Open the Menu for your full shopping list and to check items off.',
            style: TextStyle(fontSize: 22, height: 1.35),
          ),
          if (_aisleMatches.isEmpty) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => _showSpokenAisleSheet(employeeMode: false),
                child: const Text('Get Help from store employee'),
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onGoToShelf,
                    style: ElevatedButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Go To Shelf Scan'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _onNextAisle,
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Next Aisle'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShelfResults() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _shelfStatusMessage.isEmpty
                ? 'Scan complete. Open the Menu for your list.'
                : _shelfStatusMessage,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text(
            'Use the Menu to see all items and check them off.',
            style: TextStyle(fontSize: 22, height: 1.35),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onGoToShelf,
                    style: ElevatedButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Scan Another Shelf'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _onNextAisle,
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Next Aisle'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}