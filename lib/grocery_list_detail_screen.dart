import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_language.dart';
import 'app_speech.dart';
import 'app_voice_policy.dart';
import 'main.dart';
import 'shopping_voice_host.dart';

/// Displays items in a grocery list and allows adding / toggling / deleting
/// them. Items can be added manually (typed) or via a guided voice flow where
/// TTS asks for the name and section and STT captures the answers.
class GroceryListDetailScreen extends StatefulWidget {
  final String listId;
  final String listTitle;

  const GroceryListDetailScreen({
    super.key,
    required this.listId,
    required this.listTitle,
  });

  @override
  State<GroceryListDetailScreen> createState() =>
      _GroceryListDetailScreenState();
}

class _GroceryListDetailScreenState extends State<GroceryListDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  final FlutterTts _tts = FlutterTts();
  bool _speechAvailable = false;
  ShoppingVoiceHost? _listVoiceHost;

  @override
  void initState() {
    super.initState();
    AppLanguageController.instance.addListener(_syncListTts);
    unawaited(_syncListTts());
    _fetchItems();
    _initSpeech();
    if (!VlmShoppingSession.active) {
      _listVoiceHost = ShoppingVoiceHost(
        onEndShopping: () async {
          if (!mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        onOpenShoppingList: () async {
          if (!mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        onOpenAddItem: () async {
          if (!mounted) return;
          _showInputModeDialog();
        },
      )..mount();
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await AppSpeech.I.ensureInitialized(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _syncListTts() async {
    await AppLanguageController.instance.applyToTts(_tts);
  }

  @override
  void dispose() {
    AppLanguageController.instance.removeListener(_syncListTts);
    _listVoiceHost?.unmount();
    _tts.stop();
    AppSpeech.I.stt.stop();
    super.dispose();
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  Future<void> _fetchItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await supabase
          .from('grocery_items')
          .select()
          .eq('list_id', widget.listId)
          .order('name');

      setState(() => _items = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Inserts one row; [category] is the user-facing “section” (DB column name).
  Future<bool> _addItem(String name, String category) async {
    final userId = supabase.auth.currentUser?.id;
    try {
      await supabase.from('grocery_items').insert({
        'list_id': widget.listId,
        'user_id': userId,
        'name': name,
        'category': category,
        'is_checked': false,
      });
      _fetchItems();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error adding item: $e'),
            backgroundColor: const Color(0xFFFF6B6B)),
      );
      return false;
    }
  }

  Future<void> _toggleItem(String itemId, bool current) async {
    try {
      await supabase
          .from('grocery_items')
          .update({'is_checked': !current})
          .eq('id', itemId);
      _fetchItems();
    } catch (_) {}
  }

  Future<void> _confirmDeleteItem(
      String itemId, String itemName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this item?',
              style: TextStyle(fontSize: 20),
            ),
            if (itemName.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                itemName.trim(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _deleteItem(itemId);
  }

  Future<void> _deleteItem(String itemId) async {
    try {
      await supabase.from('grocery_items').delete().eq('id', itemId);
      _fetchItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: const Color(0xFFFF6B6B)),
      );
    }
  }

  // ── Input mode chooser ────────────────────────────────────────────────────

  void _showInputModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How do you want to add an item?'),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6D5EF5),
                child: const Icon(Icons.keyboard_alt_outlined,
                    color: Colors.black),
              ),
              title: const Text('Type it manually',
                  style: TextStyle(fontSize: 20)),
              subtitle: const Text('Fill in item name and section',
                  style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _showManualAddDialog();
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: CircleAvatar(
                backgroundColor:
                    _speechAvailable ? const Color(0xFF3AE4C2) : Colors.grey,
                child: Icon(Icons.mic,
                    color: _speechAvailable ? Colors.black : Colors.white),
              ),
              title: const Text('Speak it',
                  style: TextStyle(fontSize: 20)),
              subtitle: Text(
                  _speechAvailable
                      ? 'Speak the item name, then type or speak any section you want'
                      : 'Not available in this browser',
                  style: const TextStyle(fontSize: 16)),
              enabled: _speechAvailable,
              onTap: _speechAvailable
                  ? () {
                      Navigator.pop(ctx);
                      _startVoiceEntry();
                    }
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ── Manual add dialog ─────────────────────────────────────────────────────

  void _showManualAddDialog() {
    final nameController = TextEditingController();
    final sectionController = TextEditingController();
    final nameFocus = FocusNode();
    final parentContext = context;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                focusNode: nameFocus,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  hintText: 'e.g. Apples',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  hintText:
                      'Type any section, e.g. Desserts, Dairy, Snacks',
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _trySubmitManualAdd(
                  parentContext: parentContext,
                  dialogContext: dialogContext,
                  setDialogState: setDialogState,
                  nameController: nameController,
                  sectionController: sectionController,
                  nameFocus: nameFocus,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _trySubmitManualAdd(
                parentContext: parentContext,
                dialogContext: dialogContext,
                setDialogState: setDialogState,
                nameController: nameController,
                sectionController: sectionController,
                nameFocus: nameFocus,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameFocus.dispose();
      nameController.dispose();
      sectionController.dispose();
    });
  }

  Future<void> _trySubmitManualAdd({
    required BuildContext parentContext,
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required TextEditingController nameController,
    required TextEditingController sectionController,
    required FocusNode nameFocus,
  }) async {
    final name = nameController.text.trim();
    final section = sectionController.text.trim();
    if (name.isEmpty) return;
    if (section.isEmpty) {
      if (!parentContext.mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(
          content: Text('Enter a section (any name you like).'),
        ),
      );
      return;
    }
    final ok = await _addItem(name, section);
    if (!dialogContext.mounted) return;
    if (ok) {
      nameController.clear();
      sectionController.clear();
      setDialogState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialogContext.mounted) nameFocus.requestFocus();
      });
    }
  }

  // ── Voice entry ───────────────────────────────────────────────────────────

  void _startVoiceEntry() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _VoiceEntrySheet(
        tts: _tts,
        onItemAdded: (name, category) => _addItem(name, category),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _items) {
      final cat = item['category'] as String? ?? 'Other';
      grouped.putIfAbsent(cat, () => []).add(item);
    }
    final sortedCategories = grouped.keys.toList()..sort();

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 32),
            onPressed: _fetchItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.error),
                        textAlign: TextAlign.center),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_basket_outlined,
                                size: 80,
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 20),
                            Text('No items yet',
                                style: theme.textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the + button to add\nyour first item.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: sortedCategories.length,
                      itemBuilder: (_, ci) {
                        final cat = sortedCategories[ci];
                        final catItems = grouped[cat]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 6),
                              child: Text(
                                cat.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            ...catItems.map((item) {
                              final checked =
                                  item['is_checked'] as bool? ?? false;
                              return ListTile(
                                leading: Checkbox(
                                  value: checked,
                                  onChanged: (_) => _toggleItem(
                                      item['id'] as String, checked),
                                ),
                                title: Text(
                                  item['name'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 22,
                                    decoration: checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: checked
                                        ? const Color(0xFFFF1744)
                                        : null,
                                    decorationThickness: checked ? 3 : null,
                                    color: Colors.white,
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Delete item',
                                  icon: Icon(Icons.delete_outline,
                                      size: 32,
                                      color: theme.colorScheme.error),
                                  onPressed: () => _confirmDeleteItem(
                                    item['id'] as String,
                                    item['name'] as String? ?? '',
                                  ),
                                ),
                              );
                            }),
                            const Divider(),
                          ],
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _showInputModeDialog,
        tooltip: 'Add item',
        child: const Icon(Icons.add, size: 40),
      ),
    );
  }
}

// ── Voice Entry Bottom Sheet ──────────────────────────────────────────────────

enum _VoiceStep { name, category, done }

class _VoiceEntrySheet extends StatefulWidget {
  final FlutterTts tts;
  final void Function(String name, String category) onItemAdded;

  const _VoiceEntrySheet({
    required this.tts,
    required this.onItemAdded,
  });

  @override
  State<_VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends State<_VoiceEntrySheet> {
  _VoiceStep _step = _VoiceStep.name;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _listeningCategory = false;
  String _recognized = '';
  String _prompt = '';
  String _itemName = '';
  bool _cancelled = false;

  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    _categoryController = TextEditingController();
    _categoryController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runFlow());
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  // ── Flow ────────────────────────────────────────────────────────────────

  Future<void> _runFlow() async {
    // Step 1 — item name
    await _speak('What item do you want to add?');
    if (_cancelled) return;

    final name = await _listenForWords();
    if (_cancelled) return;

    if (name.isEmpty) {
      await _speak("I didn't catch that. Please close and try again.");
      return;
    }

    _itemName = _capitalize(name);

    if (!mounted || _cancelled) return;
    setState(() => _step = _VoiceStep.category);

    await _speak(
      'What aisle or section is $_itemName in? Type your answer in the box, '
      'or tap the microphone to say it. You can use any section name. When ready, '
      'tap Add to list.',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (!mounted || _cancelled || AppVoicePolicy.ttsMuted) return;
    final spoken = await AppLanguageController.instance.translate(text);
    setState(() {
      _isSpeaking = true;
      _prompt = spoken;
    });
    await widget.tts.awaitSpeakCompletion(true);
    await widget.tts.speak(spoken);
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<String> _listenForWords() async {
    if (_cancelled) return '';
    _recognized = '';
    if (mounted) setState(() => _isListening = true);

    final completer = Completer<String>();

    await AppSpeech.I.stt.listen(
      onResult: (result) {
        if (mounted) setState(() => _recognized = result.recognizedWords);
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: false,
      localeId: AppLanguageController.instance.speechToTextLocaleId(),
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 13),
      onTimeout: () {
        AppSpeech.I.stt.stop();
        return _recognized;
      },
    );

    if (mounted) setState(() => _isListening = false);
    return result.trim();
  }

  Future<void> _listenForCategoryField() async {
    if (_cancelled || !mounted || _listeningCategory) return;
    await AppSpeech.I.stt.stop();
    _recognized = '';
    setState(() => _listeningCategory = true);

    final completer = Completer<String>();

    await AppSpeech.I.stt.listen(
      onResult: (result) {
        if (mounted) setState(() => _recognized = result.recognizedWords);
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: false,
      localeId: AppLanguageController.instance.speechToTextLocaleId(),
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 13),
      onTimeout: () {
        AppSpeech.I.stt.stop();
        return _recognized;
      },
    );

    if (mounted) setState(() => _listeningCategory = false);
    final trimmed = result.trim();
    if (trimmed.isNotEmpty && mounted) {
      _categoryController.text = _titleEachWord(trimmed);
    }
  }

  Future<void> _confirmVoiceAdd() async {
    final cat = _categoryController.text.trim();
    if (cat.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please type or speak a section before adding.'),
        ),
      );
      return;
    }
    if (_cancelled) return;
    await _speak('Adding $_itemName to $cat.');
    if (_cancelled) return;
    widget.onItemAdded(_itemName, cat);
    if (!mounted || _cancelled) return;
    setState(() => _step = _VoiceStep.done);
    Navigator.pop(context);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _titleEachWord(String s) {
    return s
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  void _cancel() {
    _cancelled = true;
    widget.tts.stop();
    AppSpeech.I.stt.stop();
    if (mounted) Navigator.pop(context);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Step label
            Text(
              _step == _VoiceStep.name
                  ? 'Step 1 of 2 — Item name'
                  : _step == _VoiceStep.category
                      ? 'Step 2 of 2 — Section'
                      : 'Done!',
              style: const TextStyle(color: Colors.white60, fontSize: 18),
            ),
            const SizedBox(height: 16),

            // Prompt
            Text(
              _prompt.isEmpty ? 'Starting…' : _prompt,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 24),

            if (_step == _VoiceStep.name) ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isListening
                    ? Column(
                        key: const ValueKey('listening'),
                        children: [
                          const Icon(Icons.mic,
                              size: 64, color: Color(0xFF6D5EF5)),
                          const SizedBox(height: 8),
                          const Text('Listening…',
                              style: TextStyle(
                                  color: Color(0xFF6D5EF5),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600)),
                          if (_recognized.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              '"$_recognized"',
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 20,
                                  color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      )
                    : _isSpeaking
                        ? const Column(
                            key: ValueKey('speaking'),
                            children: [
                              Icon(Icons.volume_up,
                                  size: 64, color: Color(0xFF3AE4C2)),
                              SizedBox(height: 8),
                              Text('Speaking…',
                                  style: TextStyle(
                                      color: Color(0xFF3AE4C2),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                            ],
                          )
                        : const Icon(
                            key: ValueKey('idle'),
                            Icons.hourglass_top,
                            size: 64,
                            color: Colors.white38,
                          ),
              ),
              const SizedBox(height: 24),
            ],

            if (_step == _VoiceStep.category) ...[
              if (_listeningCategory) ...[
                const Icon(Icons.mic, size: 56, color: Color(0xFF6D5EF5)),
                const SizedBox(height: 8),
                const Text(
                  'Listening for section…',
                  style: TextStyle(
                    color: Color(0xFF6D5EF5),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_recognized.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '"$_recognized"',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _categoryController,
                enabled: !_listeningCategory,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 20, color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Section',
                  hintText: 'Type anything, e.g. Desserts, Coffee, Household',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF6D5EF5)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _listeningCategory || _isSpeaking
                          ? null
                          : _listenForCategoryField,
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Speak section'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _listeningCategory || _isSpeaking
                          ? null
                          : _confirmVoiceAdd,
                      child: const Text('Add to list'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Accumulated chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_itemName.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.check_circle,
                        size: 16, color: Color(0xFF3AE4C2)),
                    label: Text('Item: $_itemName'),
                  ),
                if (_categoryController.text.trim().isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.check_circle,
                        size: 16, color: Color(0xFF3AE4C2)),
                    label: Text(_categoryController.text.trim()),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
