import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

/// Profile-driven UI and TTS language. Persists to [SharedPreferences].
class AppLanguageOption {
  const AppLanguageOption(this.label, this.googleCode);

  final String label;
  /// Code for the `translator` package (`en`, `zh-cn`, …).
  final String googleCode;
}

class AppLanguageController extends ChangeNotifier {
  AppLanguageController._();
  static final AppLanguageController instance = AppLanguageController._();

  static const prefsKey = 'user_app_language_code';

  static const List<AppLanguageOption> options = [
    AppLanguageOption('English', 'en'),
    AppLanguageOption('Mandarin Chinese', 'zh-cn'),
    AppLanguageOption('Spanish', 'es'),
    AppLanguageOption('Hindi', 'hi'),
    AppLanguageOption('French', 'fr'),
    AppLanguageOption('Arabic', 'ar'),
    AppLanguageOption('Portuguese', 'pt'),
    AppLanguageOption('Russian', 'ru'),
    AppLanguageOption('German', 'de'),
    AppLanguageOption('Japanese', 'ja'),
    AppLanguageOption('Vietnamese', 'vi'),
    AppLanguageOption('Bengali', 'bn'),
    AppLanguageOption('Urdu', 'ur'),
    AppLanguageOption('Gujarati', 'gu'),
  ];

  final GoogleTranslator _translator = GoogleTranslator();
  final Map<String, String> _cache = {};

  String _googleCode = 'en';
  String get googleCode => _googleCode;

  static AppLanguageOption? optionForCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final c = code.toLowerCase();
    for (final o in options) {
      if (o.googleCode.toLowerCase() == c) return o;
    }
    return null;
  }

  Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(prefsKey) ?? 'en';
    _googleCode = optionForCode(raw)?.googleCode ?? 'en';
    notifyListeners();
  }

  Future<void> setGoogleCode(String code) async {
    final resolved = optionForCode(code)?.googleCode ?? 'en';
    final p = await SharedPreferences.getInstance();
    await p.setString(prefsKey, resolved);
    if (resolved == _googleCode) return;
    _googleCode = resolved;
    _cache.clear();
    notifyListeners();
  }

  /// English or mixed-English source → localized when a non-English app language is set.
  Future<String> translate(String text) async {
    if (_googleCode == 'en') return text;
    final s = text.trim();
    if (s.isEmpty) return text;
    final key = '$_googleCode::$s';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final t = await _translator.translate(text, from: 'en', to: _googleCode);
      final out = t.text;
      _cache[key] = out;
      return out;
    } catch (_) {
      return text;
    }
  }

  /// FlutterTts language string (best-effort; device may fall back).
  String flutterTtsLocale() {
    switch (_googleCode) {
      case 'en':
        return 'en-US';
      case 'zh-cn':
        return 'zh-CN';
      case 'es':
        return 'es-ES';
      case 'hi':
        return 'hi-IN';
      case 'fr':
        return 'fr-FR';
      case 'ar':
        return 'ar-SA';
      case 'pt':
        return 'pt-BR';
      case 'ru':
        return 'ru-RU';
      case 'de':
        return 'de-DE';
      case 'ja':
        return 'ja-JP';
      case 'vi':
        return 'vi-VN';
      case 'bn':
        return 'bn-IN';
      case 'ur':
        return 'ur-PK';
      case 'gu':
        return 'gu-IN';
      default:
        return 'en-US';
    }
  }

  /// Locale id for [SpeechToText.listen]; null lets the engine pick a default.
  String? speechToTextLocaleId() {
    if (_googleCode == 'en') {
      return kIsWeb ? 'en-US' : null;
    }
    switch (_googleCode) {
      case 'zh-cn':
        return 'zh_CN';
      case 'es':
        return 'es_ES';
      case 'hi':
        return 'hi_IN';
      case 'fr':
        return 'fr_FR';
      case 'ar':
        return 'ar_SA';
      case 'pt':
        return 'pt_BR';
      case 'ru':
        return 'ru_RU';
      case 'de':
        return 'de_DE';
      case 'ja':
        return 'ja_JP';
      case 'vi':
        return 'vi_VN';
      case 'bn':
        return 'bn_IN';
      case 'ur':
        return 'ur_PK';
      case 'gu':
        return 'gu_IN';
      default:
        return kIsWeb ? 'en-US' : null;
    }
  }

  Future<void> applyToTts(FlutterTts tts) async {
    try {
      await tts.setLanguage(flutterTtsLocale());
    } catch (_) {}
  }
}
