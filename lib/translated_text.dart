import 'package:flutter/material.dart';

import 'app_language.dart';

/// Async-translated [Text] for the app language chosen in profile.
class Tx extends StatefulWidget {
  const Tx(
    this.english, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String english;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<Tx> createState() => _TxState();
}

class _TxState extends State<Tx> {
  Future<String>? _future;
  String? _boundEnglish;
  String? _boundCode;

  void _refreshFuture() {
    final code = AppLanguageController.instance.googleCode;
    if (_future != null &&
        _boundEnglish == widget.english &&
        _boundCode == code) {
      return;
    }
    _boundEnglish = widget.english;
    _boundCode = code;
    _future = AppLanguageController.instance.translate(widget.english);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguageController.instance,
      builder: (context, _) {
        _refreshFuture();
        if (AppLanguageController.instance.googleCode == 'en') {
          return Text(
            widget.english,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          );
        }
        return FutureBuilder<String>(
          future: _future,
          builder: (context, snap) {
            return Text(
              snap.data ?? widget.english,
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            );
          },
        );
      },
    );
  }
}
