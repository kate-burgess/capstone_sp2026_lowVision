import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

/// Guided-voice gender for [FlutterTts]. Persists with app language in prefs.
enum AppTtsVoiceGender {
  woman,
  man,
}

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
  static const prefsKeyVoiceGender = 'user_tts_voice_gender';

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

  AppTtsVoiceGender _voiceGender = AppTtsVoiceGender.woman;
  AppTtsVoiceGender get voiceGender => _voiceGender;

  static AppTtsVoiceGender? voiceGenderFromPrefsString(String? raw) {
    if (raw == null) return null;
    switch (raw.toLowerCase()) {
      case 'man':
      case 'male':
        return AppTtsVoiceGender.man;
      case 'woman':
      case 'female':
        return AppTtsVoiceGender.woman;
      default:
        return null;
    }
  }

  static String prefsStringForVoiceGender(AppTtsVoiceGender g) =>
      g == AppTtsVoiceGender.man ? 'man' : 'woman';

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
    _voiceGender =
        voiceGenderFromPrefsString(p.getString(prefsKeyVoiceGender)) ??
            AppTtsVoiceGender.woman;
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

  Future<void> setVoiceGender(AppTtsVoiceGender gender) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(prefsKeyVoiceGender, prefsStringForVoiceGender(gender));
    if (gender == _voiceGender) return;
    _voiceGender = gender;
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
      final out = await _translateInChunks(s);
      _cache[key] = out;
      return out;
    } catch (_) {
      return text;
    }
  }

  /// Google’s free endpoint truncates long strings; split on sentence boundaries.
  Future<String> _translateInChunks(String s) async {
    const limit = 3800;
    if (s.length <= limit) {
      return _translateWithFallback(s);
    }
    final buf = StringBuffer();
    var start = 0;
    while (start < s.length) {
      var end = math.min(start + limit, s.length);
      if (end < s.length) {
        final cut = s.lastIndexOf(RegExp(r'[.!?\n。！？]'), end - 1);
        if (cut > start + limit ~/ 2) {
          end = cut + 1;
        }
      }
      buf.write(await _translateWithFallback(s.substring(start, end)));
      start = end;
    }
    return buf.toString();
  }

  Future<String> _translateWithFallback(String chunk) async {
    try {
      final t =
          await _translator.translate(chunk, from: 'en', to: _googleCode);
      return t.text;
    } catch (_) {
      try {
        final t = await _translator.translate(chunk,
            from: 'auto', to: _googleCode);
        return t.text;
      } catch (_) {
        return chunk;
      }
    }
  }

  /// Try several BCP-47 / legacy forms — engines differ (Android vs iOS vs Windows).
  List<String> flutterTtsLocaleCandidates() {
    switch (_googleCode) {
      case 'en':
        return ['en-US', 'en_US', 'en-GB', 'en_GB', 'en'];
      case 'zh-cn':
        return ['zh-CN', 'zh_CN', 'cmn-CN', 'zh', 'zh-Hans', 'zh-Hans-CN'];
      case 'es':
        return ['es-ES', 'es_ES', 'es-MX', 'es_MX', 'es-US', 'es_US', 'es'];
      case 'hi':
        return ['hi-IN', 'hi_IN', 'hi'];
      case 'fr':
        return ['fr-FR', 'fr_FR', 'fr-CA', 'fr_CA', 'fr'];
      case 'ar':
        return [
          'ar-SA',
          'ar_SA',
          'ar-EG',
          'ar_EG',
          'ar-AE',
          'ar_AE',
          'ar-XB',
          'ar',
        ];
      case 'pt':
        return ['pt-BR', 'pt_BR', 'pt-PT', 'pt_PT', 'pt'];
      case 'ru':
        return ['ru-RU', 'ru_RU', 'ru'];
      case 'de':
        return ['de-DE', 'de_DE', 'de-AT', 'de_AT', 'de'];
      case 'ja':
        return ['ja-JP', 'ja_JP', 'ja'];
      case 'vi':
        return ['vi-VN', 'vi_VN', 'vi'];
      case 'bn':
        return ['bn-IN', 'bn_IN', 'bn-BD', 'bn_BD', 'bn'];
      case 'ur':
        return ['ur-PK', 'ur_PK', 'ur-IN', 'ur_IN', 'ur'];
      case 'gu':
        return [
          'gu-IN',
          'gu_IN',
          'gu-in',
          'gu_in',
          'gu',
          'gu-IN@numbers=latn',
        ];
      default:
        return ['en-US'];
    }
  }

  /// Substrings to match a platform [getVoices] entry ([locale] / [name]).
  List<String> _voiceMatchTags() {
    switch (_googleCode) {
      case 'en':
        return [
          'en-us',
          'en_us',
          'en-gb',
          'en_gb',
          'en-au',
          'en_au',
          'en-in',
          'en_in',
          'en-ca',
          'en_ca',
          'eng_us',
          'eng_gb',
          'eng_au',
          'eng_in',
          'eng-default',
          'eng_default',
          'english',
        ];
      case 'zh-cn':
        return ['zh-cn', 'zh_cn', 'cmn', 'mandarin', 'hans'];
      case 'es':
        return ['es-es', 'es_mx', 'es-us', 'es_'];
      case 'hi':
        return ['hi-in', 'hi_in', 'hi'];
      case 'fr':
        return ['fr-fr', 'fr_ca', 'fr'];
      case 'ar':
        return ['ar-sa', 'ar_eg', 'ar-ae', 'ar_ae', 'ar'];
      case 'pt':
        return ['pt-br', 'pt_pt', 'pt'];
      case 'ru':
        return ['ru-ru', 'ru_ru', 'ru'];
      case 'de':
        return ['de-de', 'de_at', 'de'];
      case 'ja':
        return ['ja-jp', 'ja_jp', 'ja'];
      case 'vi':
        return ['vi-vn', 'vi_vn', 'vi'];
      case 'bn':
        return ['bn-in', 'bn_bd', 'bn'];
      case 'ur':
        return ['ur-pk', 'ur_in', 'ur'];
      case 'gu':
        return ['gu-in', 'gu_in', 'gu', 'guj'];
      default:
        return [flutterTtsLocaleCandidates().first.toLowerCase()];
    }
  }

  /// Locale id for [SpeechToText.listen]. Web prefers BCP‑47 with hyphens.
  String? speechToTextLocaleId() {
    if (_googleCode == 'en') {
      return kIsWeb ? 'en-US' : 'en_US';
    }
    if (kIsWeb) {
      switch (_googleCode) {
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
        return 'en_US';
    }
  }

  static bool _languageSeemsAvailable(dynamic r) {
    if (r == true) return true;
    if (r is int && r >= 0) return true;
    if (r is String) {
      final s = r.toLowerCase();
      return s == 'true' || s == 'yes' || s == 'maybe';
    }
    return false;
  }

  /// Android/iOS return `1`/`0` from [FlutterTts.setLanguage]; web may differ.
  static bool _ttsSetLanguageSucceeded(dynamic r) {
    if (r == null) return false;
    if (r is bool) return r;
    if (r is num) return r != 0;
    if (r is String) {
      final s = r.toLowerCase().trim();
      return s != '0' && s != 'false' && s.isNotEmpty;
    }
    return true;
  }

  Future<bool> _trySetTtsLanguage(FlutterTts tts, String loc) async {
    try {
      final r = await tts.setLanguage(loc);
      return _ttsSetLanguageSucceeded(r);
    } catch (_) {
      return false;
    }
  }

  Future<void> _tryGoogleTtsEngine(FlutterTts tts) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final engines = await tts.getEngines;
      if (engines is! List || engines.isEmpty) return;
      for (final e in engines) {
        final name = e.toString().toLowerCase();
        if (name.contains('com.google.android.tts')) {
          await tts.setEngine(e.toString());
          return;
        }
      }
    } catch (_) {}
  }

  /// `null` = could not infer; caller may still use the voice for naturalness ranking.
  AppTtsVoiceGender? _inferVoiceGender(Map<String, dynamic> m) {
    final blob =
        '${m['gender'] ?? ''} ${m['name'] ?? ''} ${m['locale'] ?? ''}'
            .toLowerCase();
    if (blob.contains('female') ||
        blob.contains('#female') ||
        blob.contains('woman') ||
        blob.contains('lvariant-f') ||
        blob.contains('variant-f') ||
        blob.contains('smtf') ||
        RegExp(r'[-_]f\d\d').hasMatch(blob)) {
      return AppTtsVoiceGender.woman;
    }
    if (blob.contains('male') ||
        blob.contains('#male') ||
        blob.contains('lvariant-m') ||
        blob.contains('variant-m') ||
        blob.contains('smtm') ||
        RegExp(r'[-_]m\d\d').hasMatch(blob)) {
      return AppTtsVoiceGender.man;
    }
    return null;
  }

  int _naturalVoiceScore(Map<String, dynamic> m) {
    final name = '${m['name'] ?? ''}'.toLowerCase();
    final features = '${m['features'] ?? ''}'.toLowerCase();
    var score = 0;

    final q = m['quality'];
    if (q is int) {
      if (q >= 300) {
        score += 500;
      } else if (q >= 200) {
        score += 300;
      } else if (q >= 100) {
        score += 80;
      }
    }

    if (features.contains('neural')) score += 400;
    if (name.contains('wavenet') || name.contains('neural')) score += 350;
    if (name.contains('#female') ||
        name.contains('#male') ||
        name.contains('#')) {
      score += 120;
    }
    if (name.endsWith('-network')) score += 100;
    if (name.contains('-x-')) score += 60;

    if (name.contains('compact') ||
        name.contains('pico') ||
        name.contains('legacy')) {
      score -= 600;
    }
    if (name.endsWith('-default') && !name.contains('-x-')) score -= 120;

    return score;
  }

  Future<void> _pickMatchingVoice(FlutterTts tts) async {
    if (kIsWeb) return;
    final tags = _voiceMatchTags();
    if (tags.isEmpty) return;
    try {
      final raw = await tts.getVoices;
      if (raw is! List || raw.isEmpty) return;

      final matches = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final m = Map<String, dynamic>.from(entry);
        final loc = '${m['locale'] ?? ''}'.toLowerCase();
        final name = '${m['name'] ?? ''}'.toLowerCase();
        for (final t in tags) {
          if (t.isEmpty) continue;
          if (loc.contains(t) || name.contains(t)) {
            final nameS = '${m['name'] ?? ''}';
            final locS = '${m['locale'] ?? ''}';
            if (nameS.isEmpty || locS.isEmpty) continue;
            matches.add(m);
            break;
          }
        }
      }
      if (matches.isEmpty) return;

      bool matchesPreferredGender(Map<String, dynamic> m) {
        final inferred = _inferVoiceGender(m);
        return inferred == null || inferred == _voiceGender;
      }

      var pool = matches.where(matchesPreferredGender).toList();
      if (pool.isEmpty) pool = matches;

      int rank(Map<String, dynamic> m) {
        final inferred = _inferVoiceGender(m);
        var r = _naturalVoiceScore(m);
        if (inferred == _voiceGender) r += 2000;
        if (inferred != null && inferred != _voiceGender) r -= 2000;
        return r;
      }

      pool.sort((a, b) => rank(b).compareTo(rank(a)));
      final best = pool.first;
      final nameS = '${best['name'] ?? ''}';
      final locS = '${best['locale'] ?? ''}';
      if (nameS.isEmpty || locS.isEmpty) return;

      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final id = '${best['identifier'] ?? ''}';
        if (id.isNotEmpty) {
          await tts.setVoice({'identifier': id});
          return;
        }
      }
      await tts.setVoice({'name': nameS, 'locale': locS});
    } catch (_) {}
  }

  /// Binds [tts] to the closest supported voice for the current app language.
  Future<void> applyToTts(FlutterTts tts) async {
    try {
      await tts.awaitSpeakCompletion(true);
    } catch (_) {}

    final candidates = flutterTtsLocaleCandidates();

    if (kIsWeb) {
      for (final loc in candidates) {
        if (await _trySetTtsLanguage(tts, loc)) break;
      }
      return;
    }

    await _tryGoogleTtsEngine(tts);

    var languageSet = false;
    for (final loc in candidates) {
      try {
        final avail = await tts.isLanguageAvailable(loc);
        if (!_languageSeemsAvailable(avail)) continue;
        if (await _trySetTtsLanguage(tts, loc)) {
          languageSet = true;
          break;
        }
      } catch (_) {}
    }

    if (!languageSet) {
      for (final loc in candidates) {
        if (await _trySetTtsLanguage(tts, loc)) {
          languageSet = true;
          break;
        }
      }
    }

    await _pickMatchingVoice(tts);

    // Android may ignore [setLanguage] until a voice exists; re-apply after [setVoice].
    if (!kIsWeb) {
      for (final loc in candidates) {
        if (await _trySetTtsLanguage(tts, loc)) {
          languageSet = true;
          break;
        }
      }
    }

    // Only pin English when the profile language is English.
    if (!languageSet && _googleCode == 'en') {
      try {
        await tts.setLanguage('en-US');
      } catch (_) {}
    }
  }
}
