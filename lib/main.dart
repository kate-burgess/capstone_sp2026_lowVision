import 'package:flutter/material.dart';

import 'take_picture_screen_mobile.dart' if (dart.library.html) 'take_picture_screen_web.dart' as take_screen;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await take_screen.initCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low Vision OCR',
      home: const take_screen.TakePictureScreen(),
    );
  }
}
