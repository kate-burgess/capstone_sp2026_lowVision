import 'dart:async';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_speech.dart';
import 'translated_text.dart';
import 'main.dart';
import 'take_picture_screen.dart';
import 'grocery_list_detail_screen.dart';
import 'supabase_auth_screen.dart';
import 'aisle_scanner_vlm_screen.dart';
import 'profile_setup_screen.dart';

/// Shows all grocery lists belonging to the signed-in user and lets them
/// create new ones (title only at this stage; items are added on the detail
/// screen).
class GroceryListScreen extends StatefulWidget {
  const GroceryListScreen({super.key});

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  List<Map<String, dynamic>> _lists = [];
  bool _loading = true;
  String? _error;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _fetchLists();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await AppSpeech.I.ensureInitialized();
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchLists() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final data = await supabase
          .from('grocery_lists')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() => _lists = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createList(String title) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final result = await supabase
          .from('grocery_lists')
          .insert({'user_id': userId, 'title': title})
          .select()
          .single();

      if (!mounted) return;

      // Navigate directly into the new list so the user can add items.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroceryListDetailScreen(
            listId: result['id'] as String,
            listTitle: title,
          ),
        ),
      );

      _fetchLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Tx('Error creating list: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  Future<void> _deleteList(String listId) async {
    try {
      await supabase.from('grocery_lists').delete().eq('id', listId);
      _fetchLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Tx('Error deleting list: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  Future<void> _confirmDeleteList(String listId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Tx('Are you sure you want to delete this list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Tx('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Tx('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _deleteList(listId);
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    var listening = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Tx('New grocery list'),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hint: Tx('List title'),
                  ),
                  onChanged: (_) => setModal(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Ttip(
                message: 'Speak list name',
                child: IconButton(
                  icon: Icon(
                    listening ? Icons.mic : Icons.mic_none,
                    size: 28,
                  ),
                  onPressed: (!_speechAvailable || listening)
                    ? null
                    : () async {
                        setModal(() => listening = true);
                        await AppSpeech.I.stt.stop();
                        final completer = Completer<String>();
                        var heard = '';
                        try {
                          await AppSpeech.I.stt.listen(
                            onResult: (result) {
                              heard = result.recognizedWords;
                              if (result.finalResult &&
                                  !completer.isCompleted) {
                                completer.complete(result.recognizedWords);
                              }
                            },
                            listenFor: const Duration(seconds: 12),
                            pauseFor: const Duration(seconds: 3),
                            cancelOnError: true,
                            partialResults: true,
                            localeId: AppLanguageController.instance
                                .speechToTextLocaleId(),
                          );
                          final text = await completer.future.timeout(
                            const Duration(seconds: 14),
                            onTimeout: () {
                              unawaited(AppSpeech.I.stt.stop());
                              return heard;
                            },
                          );
                          await AppSpeech.I.stt.stop();
                          final t = text.trim();
                          if (t.isNotEmpty && ctx.mounted) {
                            final cur = titleController.text.trim();
                            titleController.text = cur.isEmpty
                                ? t
                                : '$cur ${t.trim()}'.trim();
                            titleController.selection =
                                TextSelection.collapsed(
                                    offset: titleController.text.length);
                          }
                        } finally {
                          if (ctx.mounted) {
                            setModal(() => listening = false);
                          }
                        }
                      },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Tx('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                _createList(title);
              },
              child: const Tx('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SupabaseAuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Tx('My Grocery Lists'),
        leading: Ttip(
          message: 'Edit profile',
          child: IconButton(
            icon: const Icon(Icons.person_outline, size: 32),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ProfileSetupScreen(isEditing: true)),
            ),
          ),
        ),
        actions: [
          Ttip(
            message: 'Sign out',
            child: IconButton(
              icon: const Icon(Icons.logout, size: 32),
              onPressed: _signOut,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tx(
                          _error!,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchLists,
                          icon: const Icon(Icons.refresh),
                          label: const Tx('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _lists.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_cart_outlined,
                                size: 80,
                                color: theme.colorScheme.primary
                                    .withOpacity(0.5)),
                            const SizedBox(height: 20),
                            Tx(
                              'No lists yet',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Tx(
                              'Tap the + button to create\nyour first grocery list.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchLists,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        itemCount: _lists.length,
                        itemBuilder: (_, i) {
                          final list = _lists[i];
                          final listId = list['id'] as String;
                          final listTitle =
                              list['title'] as String? ?? 'Untitled';
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              leading: Ttip(
                                message: 'Start grocery shopping',
                                child: IconButton(
                                  icon: Icon(Icons.shopping_cart,
                                    size: 36,
                                    color: theme.colorScheme.secondary),
                                onPressed: () async {
                                  try {
                                    final items = await supabase
                                        .from('grocery_items')
                                        .select()
                                        .eq('list_id', listId)
                                        .order('name');
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AisleScannerVlmScreen(
                                          listId: listId,
                                          listTitle: listTitle,
                                          items:
                                              List<Map<String, dynamic>>.from(
                                                  items),
                                          cameras: cameras,
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Tx('Error loading items: $e'),
                                      ),
                                    );
                                  }
                                },
                                ),
                              ),
                              title: Text(listTitle,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600)),
                              subtitle: list['created_at'] != null
                                  ? Text(
                                      _formatDate(
                                          list['created_at'] as String),
                                    )
                                  : null,
                              trailing: Ttip(
                                message: 'Delete list',
                                child: IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 32,
                                      color: theme.colorScheme.error),
                                  onPressed: () => _confirmDeleteList(listId),
                                ),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroceryListDetailScreen(
                                    listId: listId,
                                    listTitle: listTitle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: Ttip(
        message: 'New list',
        child: FloatingActionButton.large(
          onPressed: _showCreateDialog,
          child: const Icon(Icons.add, size: 40),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
