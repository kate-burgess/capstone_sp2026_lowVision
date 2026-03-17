import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

/// Displays items in a grocery list and allows adding / toggling / deleting
/// them. Items can be added manually (typed) or via a guided voice flow where
/// TTS asks for the name and category and STT captures the answers.
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
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;

  static const _categories = [
    'Produce',
    'Dairy',
    'Meat & Seafood',
    'Bakery',
    'Frozen',
    'Pantry',
    'Beverages',
    'Snacks',
    'Household',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _fetchItems();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
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

  Future<void> _addItem(String name, String category) async {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error adding item: $e'),
            backgroundColor: Colors.red),
      );
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

  Future<void> _deleteItem(String itemId) async {
    try {
      await supabase.from('grocery_items').delete().eq('id', itemId);
      _fetchItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: Colors.red),
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
                  borderRadius: BorderRadius.circular(10)),
              leading: const CircleAvatar(
                child: Icon(Icons.keyboard_alt_outlined),
              ),
              title: const Text('Type it manually'),
              subtitle: const Text('Fill in item name and category'),
              onTap: () {
                Navigator.pop(ctx);
                _showManualAddDialog();
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              leading: CircleAvatar(
                backgroundColor:
                    _speechAvailable ? Colors.deepPurple : Colors.grey,
                child: const Icon(Icons.mic, color: Colors.white),
              ),
              title: const Text('Speak it'),
              subtitle: Text(_speechAvailable
                  ? 'Voice guided — TTS will ask you questions'
                  : 'Not available in this browser'),
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
    String selectedCategory = _categories.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  hintText: 'e.g. Apples',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedCategory = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                _addItem(name, selectedCategory);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
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
        speech: _speech,
        categories: _categories,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _fetchItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.shopping_basket_outlined,
                              size: 72, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No items yet.\nTap + to add your first item.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
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
                                  const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                cat.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
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
                                    decoration: checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: checked ? Colors.grey : null,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _deleteItem(item['id'] as String),
                                ),
                              );
                            }),
                            const Divider(height: 1),
                          ],
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showInputModeDialog,
        tooltip: 'Add item',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Voice Entry Bottom Sheet ──────────────────────────────────────────────────

enum _VoiceStep { name, category, done }

class _VoiceEntrySheet extends StatefulWidget {
  final FlutterTts tts;
  final SpeechToText speech;
  final List<String> categories;
  final void Function(String name, String category) onItemAdded;

  const _VoiceEntrySheet({
    required this.tts,
    required this.speech,
    required this.categories,
    required this.onItemAdded,
  });

  @override
  State<_VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends State<_VoiceEntrySheet> {
  _VoiceStep _step = _VoiceStep.name;
  bool _isSpeaking = false;
  bool _isListening = false;
  String _recognized = '';
  String _prompt = '';
  String _itemName = '';
  String _itemCategory = '';
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runFlow());
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

    // Step 2 — category
    await _speak(
        'What category is $_itemName? Say produce, dairy, meat, bakery, '
        'frozen, pantry, beverages, snacks, household, or other.');
    if (_cancelled) return;

    final catRaw = await _listenForWords();
    if (_cancelled) return;

    _itemCategory = _matchCategory(catRaw) ?? 'Other';

    // Step 3 — confirm and save
    await _speak('Adding $_itemName to $_itemCategory.');
    widget.onItemAdded(_itemName, _itemCategory);

    if (!mounted || _cancelled) return;
    setState(() => _step = _VoiceStep.done);
    Navigator.pop(context);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (!mounted || _cancelled) return;
    setState(() {
      _isSpeaking = true;
      _prompt = text;
    });
    await widget.tts.awaitSpeakCompletion(true);
    await widget.tts.speak(text);
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<String> _listenForWords() async {
    if (_cancelled) return '';
    _recognized = '';
    if (mounted) setState(() => _isListening = true);

    final completer = Completer<String>();

    await widget.speech.listen(
      onResult: (result) {
        if (mounted) setState(() => _recognized = result.recognizedWords);
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: false,
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 13),
      onTimeout: () {
        widget.speech.stop();
        return _recognized;
      },
    );

    if (mounted) setState(() => _isListening = false);
    return result.trim();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String? _matchCategory(String input) {
    final lower = input.toLowerCase();
    for (final cat in widget.categories) {
      final words = cat.toLowerCase().split(RegExp(r'[\s&]+'));
      for (final word in words) {
        if (word.length > 2 && lower.contains(word)) return cat;
      }
    }
    return null;
  }

  void _cancel() {
    _cancelled = true;
    widget.tts.stop();
    widget.speech.stop();
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
                      ? 'Step 2 of 2 — Category'
                      : 'Done!',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 12),

            // Prompt
            Text(
              _prompt.isEmpty ? 'Starting…' : _prompt,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 28),

            // Animated mic / speaker icon
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isListening
                  ? Column(
                      key: const ValueKey('listening'),
                      children: [
                        const Icon(Icons.mic, size: 56, color: Colors.deepPurple),
                        const SizedBox(height: 6),
                        const Text('Listening…',
                            style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600)),
                        if (_recognized.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '"$_recognized"',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    )
                  : _isSpeaking
                      ? Column(
                          key: const ValueKey('speaking'),
                          children: const [
                            Icon(Icons.volume_up, size: 56, color: Colors.indigo),
                            SizedBox(height: 6),
                            Text('Speaking…',
                                style: TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.w600)),
                          ],
                        )
                      : const Icon(
                          key: ValueKey('idle'),
                          Icons.hourglass_top,
                          size: 56,
                          color: Colors.grey,
                        ),
            ),
            const SizedBox(height: 24),

            // Accumulated chips
            Wrap(
              spacing: 8,
              children: [
                if (_itemName.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.check_circle,
                        size: 16, color: Colors.green),
                    label: Text('Item: $_itemName'),
                  ),
                if (_itemCategory.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.check_circle,
                        size: 16, color: Colors.green),
                    label: Text('Category: $_itemCategory'),
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
