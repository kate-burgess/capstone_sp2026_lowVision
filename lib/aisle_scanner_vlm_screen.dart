import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'translated_text.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_language.dart';
import 'app_speech.dart';
import 'app_voice_policy.dart';
import 'grocery_list_detail_screen.dart';
import 'main.dart';
import 'ocr_config.dart';
import 'shopping_voice_host.dart';

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

String _readableAisleTitleFromOcr(String raw) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final first = lines.isEmpty ? raw.trim() : lines.first;
  final collapsed = first.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return 'this aisle';
  if (collapsed.length > 72) return '${collapsed.substring(0, 72)}…';
  return collapsed;
}

/// OCR / UI placeholder when the sign had no readable text (e.g. server default).
bool _isOcrNoTextPlaceholder(String raw) {
  final t = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return t == 'no text found' ||
      t == '(no text detected)' ||
      t.contains('no text found');
}

String _noListMatchesInAisleMessage(String rawAisleText) {
  if (_isOcrNoTextPlaceholder(rawAisleText)) {
    return 'No text found.';
  }
  final label = _readableAisleTitleFromOcr(rawAisleText);
  if (_isOcrNoTextPlaceholder(label)) {
    return 'No text found.';
  }
  return 'You are in the $label. No items from your list are in this aisle. Keep moving to the next aisle.';
}

String _aisleWalkInLine(List<_Item> matches) {
  final names = matches.map((e) => e.name).toList();
  if (names.isEmpty) return '';
  if (names.length == 1) {
    return '${names.first} is in this aisle. Walk into it.';
  }
  if (names.length == 2) {
    return '${names[0]} and ${names[1]} are in this aisle. Walk into it.';
  }
  final allButLast = names.sublist(0, names.length - 1).join(', ');
  return '$allButLast, and ${names.last} are in this aisle. Walk into it.';
}

String _humanizeShelfLocationPhrases(String input) {
  var t = input;
  void rep(String from, String to) {
    t = t.replaceAll(RegExp(RegExp.escape(from), caseSensitive: false), to);
  }

  rep('bottom left', 'bottom shelf on the left');
  rep('bottom right', 'bottom shelf on the right');
  rep('top left', 'top shelf on the left');
  rep('top right', 'top shelf on the right');
  rep('middle left', 'middle shelf on the left');
  rep('middle right', 'middle shelf on the right');
  rep('middle center', 'middle shelf in the center');
  rep('center left', 'middle shelf on the left');
  rep('center right', 'middle shelf on the right');
  rep('upper left', 'top shelf on the left');
  rep('upper right', 'top shelf on the right');
  rep('lower left', 'bottom shelf on the left');
  rep('lower right', 'bottom shelf on the right');
  return t;
}

/// Makes multi-product shelf replies easier to read (one flavor/location per line).
String _expandShelfLinesForScreenReader(String input) {
  var t = input.trim();
  if (t.isEmpty) return t;
  t = t.replaceAll(RegExp(r'\s*;\s*'), '\n');
  t = t.replaceAll(RegExp(r'\s*•\s*'), '\n');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

/// VLM sometimes answers with a bare "None." when nothing is recognized.
String _normalizeNoneItemCaption(String cleaned) {
  final one =
      cleaned.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (one == 'none' || one == 'none.') {
    return 'no item detected.';
  }
  return cleaned;
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

const _kUnreadableAisleMessage =
    'I could not read the aisle sign. Please retake the photo. If needed, tap Get Help from store employee.';

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
  final ImagePicker _picker = ImagePicker();
  late final ShoppingVoiceHost _shoppingVoiceHost;
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
  bool _shoppingMenuOpen = false;
  bool _fullScreenListOpen = false;
  bool _showAisleUnclearEmployeeOption = false;
  List<String> _menuOrder = List<String>.from(_shoppingMenuOrderDefault);

  List<_Item> _aisleMatches = [];
  List<_Item> _shelfMatches = [];
  List<_Item> _pendingShelfItems = [];
  int _shelfPromptIndex = 0;
  bool _lastShelfTargetFound = false;
  String? _lastShelfTargetName;

  /// Last captured frame shown while processing and on the results screen.
  Uint8List? _scanPreviewBytes;

  late List<_Item> _items;
  late Map<String, bool> _initialCheckedById;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map(_Item.fromMap).toList();
    _initialCheckedById = {for (final item in _items) item.id: item.isChecked};
    VlmShoppingSession.active = true;
    _shoppingVoiceHost = ShoppingVoiceHost(
      onEndShopping: () async {
        if (!mounted) return;
        await _onEndShopping();
      },
      onScanAisleSign: _voiceCommandScanAisle,
      onScanShelf: _voiceCommandScanShelf,
      onOpenShoppingList: () async {
        if (!mounted) return;
        setState(() {
          _shoppingMenuOpen = false;
          _fullScreenListOpen = true;
        });
      },
      onOpenAddItem: () async {
        if (!mounted) return;
        await _openAddItemsFromDrawer();
      },
    )..mount();
    _tts.awaitSpeakCompletion(true);
    AppLanguageController.instance.addListener(_syncTtsLanguage);
    unawaited(_syncTtsLanguage());
    _initSpeech();
    _initCamera();
    _loadMenuOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak(
        'Grocery shopping mode started for ${widget.listTitle}. Point your camera at the aisle sign and tap Scan Aisle Sign.',
      );
    });
  }

  Future<void> _syncTtsLanguage() async {
    await AppLanguageController.instance.applyToTts(_tts);
  }

  @override
  void dispose() {
    AppLanguageController.instance.removeListener(_syncTtsLanguage);
    _shoppingVoiceHost.unmount();
    VlmShoppingSession.active = false;
    _camera?.dispose();
    AppSpeech.I.stt.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await AppSpeech.I.ensureInitialized(
        onError: (err) {
          if (!mounted) return;
          final dynamic e = err;
          final msg = (() {
            try {
              final m = e.errorMsg;
              if (m is String && m.isNotEmpty) return m;
            } catch (_) {}
            return err.toString();
          })();
          if (msg.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Tx(
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

  /// Listens for an aisle name. On web, browser SpeechRecognition does not mark
  /// results [finalResult] until after [stop]; we stop then wait briefly so the
  /// plugin can promote the last partial. [onPartial] updates UI.
  ///
  /// Important: with both [listenFor] and [pauseFor], the plugin's first timer
  /// uses **min** of the two—so pauseFor 5s ended listening ~5s after start even
  /// when listenFor was 30s. That cut off speech right after TTS. Web uses
  /// pauseFor: null so only listenFor limits the session.
  Future<String> _listenForSpokenAislePhrase({
    void Function(String partial)? onPartial,
  }) async {
    if (!_speechAvailable) return '';

    await _tts.stop();
    await Future<void>.delayed(
      Duration(milliseconds: kIsWeb ? 1400 : 600),
    );

    var recognized = '';
    final done = Completer<void>();
    final stopRequested = Completer<void>();
    _stopAisleListenRequested = stopRequested;

    void maybeFinish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      if (AppSpeech.I.stt.isListening) {
        await AppSpeech.I.stt.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      try {
        await AppSpeech.I.stt.listen(
          onResult: (result) {
            recognized = result.recognizedWords;
            if (recognized.isNotEmpty) {
              onPartial?.call(recognized);
            }
            if (result.finalResult) {
              maybeFinish();
            }
          },
          listenFor: Duration(seconds: kIsWeb ? 60 : 30),
          pauseFor: kIsWeb ? null : const Duration(seconds: 8),
          localeId: AppLanguageController.instance.speechToTextLocaleId(),
          listenOptions: SpeechListenOptions(
            listenMode:
                kIsWeb ? ListenMode.confirmation : ListenMode.dictation,
            partialResults: true,
            cancelOnError: false,
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Tx(
                'Could not start speech listening: $e',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        }
        return '';
      }

      await Future.any<void>([
        done.future,
        stopRequested.future,
        Future<void>.delayed(Duration(seconds: kIsWeb ? 62 : 32)),
      ]);

      if (AppSpeech.I.stt.isListening) {
        await AppSpeech.I.stt.stop();
      }

      if (kIsWeb && !done.isCompleted) {
        await Future.any<void>([
          done.future,
          Future<void>.delayed(const Duration(milliseconds: 2500)),
        ]);
      }
    } finally {
      _stopAisleListenRequested = null;
      if (AppSpeech.I.stt.isListening) {
        await AppSpeech.I.stt.stop();
      }
      await Future<void>.delayed(Duration(milliseconds: kIsWeb ? 800 : 400));
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

  /// Stops the live preview after a capture or gallery pick so the stream
  /// does not keep running during OCR / VLM.
  Future<void> _stopLiveCamera() async {
    await _camera?.dispose();
    _camera = null;
    _cameraReady = false;
  }

  Future<void> _clearPreviewAndRestartCamera() async {
    if (!mounted) return;
    setState(() => _scanPreviewBytes = null);
    await _restartCamera();
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

      var detail = body.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (detail.length > 180) {
        detail = '${detail.substring(0, 180)}…';
      }
      final buf = StringBuffer('OCR server error ${res.statusCode}.');
      if (detail.isNotEmpty) {
        buf.write(' $detail');
      }
      if (kIsWeb && ocrWebMissingBuildTimeUrl()) {
        buf.write(
          ' Deployed sites need OCR_BASE_URL at build time, e.g. '
          'flutter build web --dart-define=OCR_BASE_URL=https://your-api.example '
          '(HTTPS if your app is HTTPS). The camera preview can still work when OCR fails.',
        );
      } else if (kIsWeb && res.statusCode >= 500) {
        buf.write(
          ' Check your OCR or grocery scan server logs and CORS. The camera preview can still work when OCR fails.',
        );
      }
      setState(() => _error = buf.toString());
      return null;
    } catch (_) {
      var msg =
          'Cannot reach OCR service at ${ocrServiceBaseUrl()}. If this is a deployed web app, rebuild with --dart-define=OCR_BASE_URL=<your HTTPS API>.';
      if (kIsWeb && ocrWebMissingBuildTimeUrl()) {
        msg =
            'OCR is not pointed at a reachable server. Build with --dart-define=OCR_BASE_URL=https://your-ocr-api.example (HTTPS on Vercel). The camera preview can still work.';
      }
      setState(() => _error = msg);
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
            return 'Grocery scan server error ${res.statusCode}: ${decoded['error']}';
          }
        } catch (_) {}
        final snippet = body.trim();
        return snippet.isEmpty
            ? 'Grocery scan server error ${res.statusCode}.'
            : 'Grocery scan server error ${res.statusCode}: $snippet';
      }

      final decoded = json.decode(body) as Map<String, dynamic>;
      final answer = (decoded['answer'] as String? ?? '').trim();
      return answer.isEmpty ? 'No description returned.' : answer;
    } catch (e) {
      return 'Grocery scan request failed: $e';
    }
  }

  bool _vlmSaysItemFound(String answer) {
    final upper = answer.toUpperCase();
    // Important: "ITEM NOT FOUND" contains the substring "ITEM FOUND".
    if (upper.contains('ITEM NOT FOUND')) return false;
    return RegExp(r'\bITEM FOUND\b').hasMatch(upper);
  }

  /// Strips VLM footer phrases so the visible summary matches our [targetFound] logic.
  String _vlmAnswerWithoutFoundTags(String answer) {
    var s = answer.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(RegExp(r'\bITEM\s+NOT\s+FOUND\b', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\bITEM\s+FOUND\b', caseSensitive: false), '');
    // Preserve line breaks so multi-brand / multi-flavor lists stay readable.
    final lines = s.split(RegExp(r'\r?\n'));
    s = lines
        .map((line) {
          var t = line.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
          t = t.replaceAll(RegExp(r'^\s*[.,;:]\s*'), '').trim();
          t = t.replaceAll(RegExp(r'\s*[.,;:]\s*$'), '').trim();
          return t;
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return s;
  }

  String _buildShelfStatusMessage({
    required String vlmAnswer,
    required String matchedNames,
    required _Item? target,
    required bool targetFound,
  }) {
    final cleanedRaw = _vlmAnswerWithoutFoundTags(vlmAnswer);
    final cleaned = _normalizeNoneItemCaption(
      _expandShelfLinesForScreenReader(
        _humanizeShelfLocationPhrases(cleanedRaw),
      ),
    );
    final hasMatches = matchedNames.isNotEmpty;

    if (target != null && !targetFound) {
      return 'No ${target.name} found. Keep moving along the aisle.';
    }

    if (target == null) {
      if (!hasMatches) {
        return cleaned.isEmpty
            ? 'Nothing clear on this shelf yet.'
            : cleaned;
      }
      return cleaned.isEmpty
          ? 'Nothing clear on this shelf yet.'
          : cleaned;
    }

    // target != null && targetFound — show vision description only (no name prefix).
    if (cleaned.isEmpty) {
      return 'Looks like a match.';
    }
    return cleaned;
  }

  bool _vlmAnswerMatchesTarget(String answer, _Item target) {
    final answerWords = _tokenize(answer);
    final targetWords = _tokenize(target.name);
    for (final t in targetWords) {
      if (answerWords.any((w) => _isFuzzyTokenMatch(t, w))) return true;
    }
    return false;
  }

  /// Returns true when the model explicitly says the target is NOT present,
  /// e.g. "not banana", "is not bananas", "isn't banana".
  bool _vlmExplicitlyRejectsTarget(String answer, _Item target) {
    final a = answer.toLowerCase();
    final t = target.name.toLowerCase().trim();
    if (t.isEmpty) return false;
    final escapedTarget = RegExp.escape(t);

    final directNegation = RegExp(
      "\\b(?:not|no|is not|isn't|isnt)\\s+(?:a|an|the\\s+)?$escapedTarget\\b",
      caseSensitive: false,
    );
    if (directNegation.hasMatch(a)) return true;

    // Also catch cases like "banana is not here" / "bananas not found".
    final targetThenNegation = RegExp(
      "$escapedTarget\\b.{0,24}\\b(?:not|no|isn't|isnt|not found)\\b",
      caseSensitive: false,
    );
    return targetThenNegation.hasMatch(a);
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

    await _stopLiveCamera();
    if (!mounted) return;
    setState(() {
      _scanPreviewBytes = bytes;
      _loading = true;
      _error = null;
      _showAisleUnclearEmployeeOption = false;
    });

    await _speak('Reading aisle sign.');

    final text = await _runOcr(bytes);

    setState(() => _loading = false);

    if (text == null) {
      final unreadable =
          await AppLanguageController.instance.translate(_kUnreadableAisleMessage);
      setState(() {
        _showAisleUnclearEmployeeOption = true;
        _aisleStatusMessage = unreadable;
      });
      await _announceTts(unreadable);
      await _clearPreviewAndRestartCamera();
      return;
    }

    _aisleOcrText = text;

    if (!_looksLikeUsefulAisleText(text)) {
      final unreadable =
          await AppLanguageController.instance.translate(_kUnreadableAisleMessage);
      setState(() {
        _phase = _Phase.aisleSign;
        _aisleStatusMessage = unreadable;
        _showAisleUnclearEmployeeOption = true;
      });
      await _announceTts(unreadable);
      await _clearPreviewAndRestartCamera();
      return;
    }

    setState(() => _showAisleUnclearEmployeeOption = false);

    _aisleMatches = _matchItems(text);
    _pendingShelfItems = _aisleMatches.where((i) => !i.isChecked).toList();
    _shelfPromptIndex = 0;

    for (final item in _aisleMatches) {
      item.aisle ??= _currentAisle;
    }

    final aisleEn = _aisleMatches.isEmpty
        ? _noListMatchesInAisleMessage(text)
        : _aisleWalkInLine(_aisleMatches);
    final aisleUser = await AppLanguageController.instance.translate(aisleEn);
    setState(() {
      _phase = _Phase.aisleResults;
      _aisleStatusMessage = aisleUser;
    });

    await _announceTts(aisleUser);
  }

  Future<void> _voiceCommandScanAisle() async {
    if (!mounted) return;
    if (_loading || _takingPicture) {
      await _speak('Wait for the current step to finish.');
      return;
    }
    if (_shoppingMenuOpen) {
      setState(() => _shoppingMenuOpen = false);
    }
    if (_fullScreenListOpen) {
      _closeFullScreenList();
    }
    if (_phase == _Phase.aisleSign) {
      await _onScanAisleSign();
      return;
    }
    if (_phase == _Phase.aisleResults ||
        _phase == _Phase.shelfResults ||
        _phase == _Phase.shelf) {
      setState(() {
        _scanPreviewBytes = null;
        _phase = _Phase.aisleSign;
        _aisleStatusMessage = '';
        _shelfStatusMessage = '';
      });
      await _restartCamera();
      await _onScanAisleSign();
    }
  }

  Future<void> _voiceCommandScanShelf() async {
    if (!mounted) return;
    if (_loading || _takingPicture) {
      await _speak('Wait for the current step to finish.');
      return;
    }
    if (_shoppingMenuOpen) {
      setState(() => _shoppingMenuOpen = false);
    }
    if (_fullScreenListOpen) {
      _closeFullScreenList();
    }
    if (_phase == _Phase.aisleSign) {
      await _speak('Scan the aisle sign first, then you can scan a shelf.');
      return;
    }
    if (_phase == _Phase.aisleResults) {
      await _onGoToShelf();
      return;
    }
    if (_phase == _Phase.shelf) {
      await _onScanShelf();
      return;
    }
    if (_phase == _Phase.shelfResults) {
      setState(() {
        _scanPreviewBytes = null;
        _phase = _Phase.shelf;
        _shelfStatusMessage = '';
      });
      await _restartCamera();
      await _onScanShelf();
    }
  }

  Future<void> _onGoToShelf() async {
    setState(() {
      _scanPreviewBytes = null;
      _phase = _Phase.shelf;
      _shelfStatusMessage = '';
      _shelfOcrText = '';
      _vlmAnswer = '';
      _shelfMatches = [];
      _lastShelfTargetFound = false;
      _lastShelfTargetName = null;
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

    await _stopLiveCamera();
    if (!mounted) return;
    setState(() {
      _scanPreviewBytes = bytes;
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
        'Check if any visible product visually matches "${target.name}" (include the exact type or flavor if that matters, not only the brand). '
        'If it matches, give one short sentence with the full product name including flavor or variant if visible, and its approximate position using phrases like top shelf on the left or middle shelf on the right. '
        'End with: ITEM FOUND. '
        'If nothing matches, say: MOVE ALONG, NO ITEMS FOUND. '
        'Be concise.';
    } else {
      question =
        'Do NOT read any text, labels, or signs. Use only visual appearance. '
        'List EVERY distinct branded product or package you can clearly see in this image, across the whole frame: left to right and top to bottom, including smaller or partly hidden items when you can tell what they are. '
        'Do not stop after one or two big items—keep going until each clearly separate product has its own line. '
        'Each flavor or variety of the same brand counts as a separate product with its own line. '
        'Each line must be: full product name with flavor if visible, then a dash or comma, then that item’s shelf position (phrases like top shelf on the left or middle shelf on the right). '
        'Example format (style only):\n'
        'Cheerios Honey Nut — middle shelf on the right\n'
        'Cheerios Original — top shelf on the left\n'
        'Never merge two different products or two flavors into one line. Never answer with only a single brand name if several different products are visible. '
        'Put one line break after each product.';
    }

    final vlmAnswer = await _runVlmPredict(bytes, question: question);

    setState(() => _loading = false);

    if (shelfText == null) {
      await _speak('Could not read the shelf text. Please try again.');
      await _clearPreviewAndRestartCamera();
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
    final answerRejectsTarget =
        target != null && _vlmExplicitlyRejectsTarget(vlmAnswer, target);
    final targetOnShelfByOcr =
        target != null && _itemMatchesText(target, _tokenize(shelfText));
    final shelfMatchesOtherListItem = target != null &&
        _shelfMatches.any((i) => !identical(i, target));

    final targetFound = target != null &&
        vlmSaysFound &&
        answerNamesTarget &&
        !answerRejectsTarget &&
        (targetOnShelfByOcr || !shelfMatchesOtherListItem);

    final shelfEn = _buildShelfStatusMessage(
      vlmAnswer: vlmAnswer,
      matchedNames: matchedNames,
      target: target,
      targetFound: targetFound,
    );
    final shelfUser = await AppLanguageController.instance.translate(shelfEn);
    setState(() {
      _shelfStatusMessage = shelfUser;
      _phase = _Phase.shelfResults;
      _lastShelfTargetFound = targetFound;
      _lastShelfTargetName = target?.name;
    });

    await _announceTts(shelfUser);

    if (target != null && targetFound) {
      if (!mounted) return;
      final wantCheck = await _showCheckOffItemDialog(itemName: target.name);
      if (!mounted) return;
      if (wantCheck == true) {
        setState(() => target.isChecked = true);
        await _saveItemCheckedState(target);
        await _speak('${target.name} checked off.');
      } else if (wantCheck == false) {
        await _speak('Okay. ${target.name} is still on your list.');
      }
      await _speak('Go to the next aisle and scan.');
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
            child: Tx(
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

  Future<bool?> _showCheckOffItemDialog({required String itemName}) async {
    await _speak(
      'This looks like a match for $itemName. Do you want to check it off your list? Yes or no.',
    );
    if (!mounted) return null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Tx(
          'Looks like a match',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Tx(
                    'Looking for: ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Tx(
                'Do you want to check this item off your list?',
                style: TextStyle(fontSize: 24, height: 1.3),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _checkOffAnswerBox(
                      label: 'Yes',
                      borderColor: const Color(0xFF3AE4C2),
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _checkOffAnswerBox(
                      label: 'No',
                      borderColor: const Color(0xFF6D5EF5),
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
      _scanPreviewBytes = null;
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
      _lastShelfTargetFound = false;
      _lastShelfTargetName = null;
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
        SnackBar(content: Tx('Could not refresh list: $e')),
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
          content: Tx(
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
      final msg = await AppLanguageController.instance
          .translate(_noListMatchesInAisleMessage(value));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      );
      await _announceTts(msg);
      return;
    }

    final walkIn = _aisleWalkInLine(matches);
    final walkInUser = await AppLanguageController.instance.translate(walkIn);
    setState(() {
      _currentAisleLabel = value;
      _phase = _Phase.aisleResults;
      _aisleOcrText = value;
      _aisleStatusMessage = walkInUser;
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
    await _announceTts(walkInUser);
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
              title: Tx(
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
                          color: const Color(0xFF3AE4C2).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF3AE4C2),
                            width: 2,
                          ),
                        ),
                        child: const Tx(
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
                      const Tx(
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
                        label: Tx('Type aisle name'),
                        hint: Tx('e.g. dairy, bakery, produce'),
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
                        child: Tx(
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
                      label: Tx(
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
                          await AppSpeech.I.stt.stop();
                        },
                        child: const Tx(
                          'Stop listening',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Tx(
                        'Allow the microphone if your browser asks. Wait until '
                        'the voice prompt finishes, then speak clearly—you should '
                        'see words appear. On the web, you have up to about a '
                        'minute; tap Stop listening when finished.',
                        style: TextStyle(fontSize: 17, color: Colors.white60),
                      ),
                    ],
                    const SizedBox(height: 16),
                    transcript.isEmpty
                        ? Tx(
                            'Heard text will appear here.',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                              color: Colors.white54,
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Tx(
                                'Heard: ',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  transcript,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Tx('Cancel', style: TextStyle(fontSize: 20)),
                ),
                FilledButton(
                  onPressed: !hasValue
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _applyAisleValueFromString(combinedValue());
                        },
                  child:
                      const Tx('Use this aisle', style: TextStyle(fontSize: 20)),
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
      if (AppSpeech.I.stt.isListening) {
        await AppSpeech.I.stt.stop();
      }
      // Avoid disposing immediately here: the dialog can still be in the
      // teardown/rebuild phase on web, and disposing too early can trigger
      // "TextEditingController used after being disposed".
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
            backgroundColor: const Color(0xFF6D5EF5),
            foregroundColor: Colors.white,
            iconColor: Colors.white,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            textStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 44, color: Colors.white),
              const SizedBox(width: 20),
              Expanded(child: Tx(label, maxLines: 2)),
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
          label: AppVoicePolicy.ttsMuted ? 'Unmute audio' : 'Mute audio',
          semanticLabel: AppVoicePolicy.ttsMuted
              ? 'Turn spoken feedback back on'
              : 'Mute spoken feedback',
          icon: AppVoicePolicy.ttsMuted ? Icons.volume_off : Icons.volume_up,
          onPressed: () {
            setState(() {
              AppVoicePolicy.toggleMute();
              if (AppVoicePolicy.ttsMuted) _tts.stop();
            });
          },
        );
      case _kMenuList:
        return _largeMenuButton(
          label: 'Shopping list',
          semanticLabel:
              'Open full screen shopping list and add items',
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
                  child: Icon(Icons.drag_handle, size: 48, color: Colors.white70),
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
              Tx(
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
              Tx(
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
                  child: const Tx('Resume shopping'),
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
        SnackBar(content: Tx('Could not save "${item.name}".')),
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

  Future<void> _announceTts(String text) async {
    if (mounted) {
      setState(() => _lastSpoken = text);
    } else {
      _lastSpoken = text;
    }
    if (AppVoicePolicy.ttsMuted || !mounted) return;
    await _tts.speak(text);
  }

  Future<void> _speak(String english) async {
    final text = await AppLanguageController.instance.translate(english);
    await _announceTts(text);
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
                  color: const Color(0xFF6D5EF5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 44,
                    minWidth: 76,
                    maxWidth: 108,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Tx(
                        'Menu',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
    final title = 'Grocery Aisle $_currentAisleLabel';

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
          title: Tx(
            _fullScreenListOpen
                ? 'Shopping list'
                : _shoppingMenuOpen
                    ? 'Menu'
                    : title,
          ),
          leading: _fullScreenListOpen
              ? Ttip(
                  message: 'Close list',
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _closeFullScreenList,
                  ),
                )
              : _shoppingMenuOpen
                  ? Ttip(
                      message: 'Close menu',
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _closeShoppingMenuWithCameraResume,
                      ),
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
              Tx(
                'Tap items to check them off. Use Add items for more.',
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart, size: 28),
                  label: const Tx(
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
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              decoration: item.isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: item.isChecked
                                  ? const Color(0xFFFF1744)
                                  : null,
                              decorationThickness: item.isChecked ? 3 : null,
                              color: Colors.white,
                            ),
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
                  child: const Tx('Back to shopping'),
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
    final showFrozenFrame = _scanPreviewBytes != null;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Tx(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                )
              else if (showFrozenFrame)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Image.memory(
                          _scanPreviewBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (_loading)
                      Container(
                        color: Colors.black54,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                )
              else if (!_cameraReady)
                const Center(child: CircularProgressIndicator())
              else
                CameraPreview(_camera!),

              if (!showFrozenFrame) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(16),
                    child: isAisle
                        ? const Tx(
                            'Point at the aisle sign',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 22),
                          )
                        : target != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Tx(
                                    'Point at shelf for:',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                    ),
                                  ),
                                  Text(
                                    target.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              )
                            : const Tx(
                                'Point at the shelf',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                ),
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
                      iconSize: 32,
                      onPressed: _flipCamera,
                      icon: const Icon(Icons.cameraswitch,
                          color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ],
              if (showFrozenFrame && _loading)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(16),
                    child: const Tx(
                      'Processing photo…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22),
                    ),
                  ),
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
                  child: Tx(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF6B6B)),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_loading || _takingPicture)
                          ? null
                          : (isAisle ? _onScanAisleSign : _onScanShelf),
                      child: Tx(isAisle ? 'Scan Aisle Sign' : 'Scan Shelf'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_loading || _takingPicture)
                          ? null
                          : () => isAisle
                              ? _onScanAisleSign(fromGallery: true)
                              : _onScanShelf(fromGallery: true),
                      child: const Tx('Use Gallery Image'),
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
                    child: const Tx('Get Help from store employee'),
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
    final preview = _scanPreviewBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null)
          Expanded(
            flex: 5,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Image.memory(preview, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        Expanded(
          flex: preview != null ? 4 : 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  label: _aisleStatusMessage,
                  child: Text(
                    _aisleStatusMessage,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
                if (_aisleMatches.isEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () =>
                          _showSpokenAisleSheet(employeeMode: false),
                      child: const Tx('Get Help from store employee'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
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
                          child: const Tx('Scan Shelf'),
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
                          child: const Tx('Next Aisle'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShelfResults() {
    final shouldShowMoveAlongRescan =
        _lastShelfTargetName != null && !_lastShelfTargetFound;
    final preview = _scanPreviewBytes;
    final shelfStatusEmpty = _shelfStatusMessage.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null)
          Expanded(
            flex: 5,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Image.memory(preview, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        Expanded(
          flex: preview != null ? 4 : 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  label: shelfStatusEmpty
                      ? 'Shelf scan finished.'
                      : _shelfStatusMessage,
                  child: shelfStatusEmpty
                      ? const Tx(
                          'Shelf scan finished.',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        )
                      : Text(
                          _shelfStatusMessage,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
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
                          child: Tx(
                            shouldShowMoveAlongRescan
                                ? 'Move Along Aisle & Re-Scan'
                                : 'Scan Shelf',
                          ),
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
                          child: const Tx('Next Aisle'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (shouldShowMoveAlongRescan) ...[
                  const SizedBox(height: 12),
                  const Tx(
                    'Take a few steps along this aisle and scan the shelf again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
