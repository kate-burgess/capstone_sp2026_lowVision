import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// English-only TTS: set language once and use the engine default voice.
/// Avoids [FlutterTts.setVoice] so prompts and read-aloud use the same voice.
Future<void> applyEnglishTts(FlutterTts tts) async {
  try {
    await tts.awaitSpeakCompletion(true);
  } catch (_) {}

  if (kIsWeb) {
    try {
      await tts.setLanguage('en-US');
    } catch (_) {}
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final engines = await tts.getEngines;
      if (engines is List) {
        for (final e in engines) {
          if (e.toString().toLowerCase().contains('com.google.android.tts')) {
            await tts.setEngine(e.toString());
            break;
          }
        }
      }
    } catch (_) {}
  }

  for (final loc in ['en-US', 'en_US', 'en-GB', 'en_GB', 'en']) {
    try {
      await tts.setLanguage(loc);
      return;
    } catch (_) {}
  }
}

/// Locale for [SpeechToText.listen] in English.
String? englishSpeechToTextLocaleId() {
  if (kIsWeb) return 'en-US';
  return 'en_US';
}
