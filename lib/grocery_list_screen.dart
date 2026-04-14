import 'dart:async';

import 'package:flutter/material.dart';

import 'app_tts.dart';
import 'app_speech.dart';
import 'main.dart';
import 'take_picture_screen.dart';
import 'grocery_list_detail_screen.dart';
import 'supabase_auth_screen.dart';
import 'aisle_scanner_vlm_screen.dart';
import 'profile_setup_screen.dart';
import 'grocery_list_duplicate.dart';
import 'grocery_ui.dart';

enum _ListsTimeFilter { all, lastList, threeMonths, sixMonths }

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
  final Map<String, ({int total, int done})> _listProgress = {};
  bool _loading = true;
  String? _error;
  bool _speechAvailable = false;
  _ListsTimeFilter _timeFilter = _ListsTimeFilter.all;

  DateTime? _listCreatedAt(Map<String, dynamic> list) {
    final v = list['created_at'];
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Calendar-based “N months ago” for filter cutoffs.
  DateTime _monthsEarlier(int months) {
    final n = DateTime.now();
    return DateTime(n.year, n.month - months, n.day);
  }

  List<Map<String, dynamic>> _filteredLists() {
    switch (_timeFilter) {
      case _ListsTimeFilter.all:
        return List<Map<String, dynamic>>.from(_lists);
      case _ListsTimeFilter.lastList:
        return _lists.isEmpty ? [] : [_lists.first];
      case _ListsTimeFilter.threeMonths:
        final cutoff = _monthsEarlier(3);
        return _lists.where((l) {
          final t = _listCreatedAt(l);
          return t != null && !t.isBefore(cutoff);
        }).toList();
      case _ListsTimeFilter.sixMonths:
        final cutoff = _monthsEarlier(6);
        return _lists.where((l) {
          final t = _listCreatedAt(l);
          return t != null && !t.isBefore(cutoff);
        }).toList();
    }
  }

  Widget _buildListTimeFilterStrip(ThemeData theme) {
    Widget chip(_ListsTimeFilter value, String label) {
      final selected = _timeFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _timeFilter = value),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? kBrandPurpleMid
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? kBrandPurpleLight.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.12),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: kBrandPurpleMid.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF2A2A2A),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            chip(_ListsTimeFilter.all, 'All lists'),
            chip(_ListsTimeFilter.lastList, 'Last list'),
            chip(_ListsTimeFilter.threeMonths, '3 months'),
            chip(_ListsTimeFilter.sixMonths, '6 months'),
          ],
        ),
      ),
    );
  }

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

      final lists = List<Map<String, dynamic>>.from(data);
      final progress = <String, ({int total, int done})>{};
      if (lists.isNotEmpty) {
        try {
          final itemRows = await supabase
              .from('grocery_items')
              .select('list_id,is_checked')
              .eq('user_id', userId);
          final rows = List<Map<String, dynamic>>.from(itemRows);
          for (final row in rows) {
            final lid = row['list_id'] as String?;
            if (lid == null) continue;
            final cur = progress[lid] ?? (total: 0, done: 0);
            final checked = row['is_checked'] as bool? ?? false;
            progress[lid] = (
              total: cur.total + 1,
              done: cur.done + (checked ? 1 : 0),
            );
          }
        } catch (_) {
          // Lists still load; progress bars show empty if item counts fail.
        }
      }

      setState(() {
        _lists = lists;
        _listProgress
          ..clear()
          ..addAll(progress);
      });
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
          content: Text('Error creating list: $e'),
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
          content: Text('Error deleting list: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  Future<void> _confirmDeleteList(String listId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Are you sure you want to delete this list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _deleteList(listId);
  }

  Future<void> _renameListDialog(String listId, String currentTitle) async {
    final c = TextEditingController(text: currentTitle);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'List name',
            hintText: 'e.g. Weekly shop — next week',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null || next.isEmpty || !mounted) return;
    try {
      await supabase.from('grocery_lists').update({'title': next}).eq('id', listId);
      _fetchLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not rename: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  Future<void> _duplicateListDialog(String listId, String listTitle) async {
    final c = TextEditingController(text: '$listTitle (next week)');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate list'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New list name',
            hintText: 'Name for your copy',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Create copy'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    try {
      final newId = await duplicateGroceryList(
        sourceListId: listId,
        newTitle: title,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroceryListDetailScreen(
            listId: newId,
            listTitle: title,
          ),
        ),
      );
      _fetchLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not duplicate: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    var listening = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('New grocery list'),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hint: Text('List title'),
                  ),
                  onChanged: (_) => setModal(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
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
                            localeId: englishSpeechToTextLocaleId(),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                _createList(title);
              },
              child: const Text('Create'),
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
    final filtered = _filteredLists();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grocery Lists'),
        leading: Tooltip(
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
          Tooltip(
            message: 'Sign out',
            child: IconButton(
              icon: const Icon(Icons.logout, size: 32),
              onPressed: _signOut,
            ),
          ),
        ],
      ),
      body: GroceryAmbientBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: groceryPagePadding(context).add(
                        const EdgeInsets.symmetric(vertical: 24),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: groceryMaxContentWidth(context),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _fetchLists,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _lists.isEmpty
                    ? Center(
                        child: Padding(
                          padding: groceryPagePadding(context).add(
                            const EdgeInsets.all(24),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: groceryMaxContentWidth(context),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 88,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.65),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'No lists yet',
                                  style: theme.textTheme.headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + to start your first grocery run.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildListTimeFilterStrip(theme),
                          Padding(
                            padding: groceryPagePadding(context).copyWith(
                              top: 6,
                              bottom: 2,
                            ),
                            child: Text(
                              '${filtered.length} of ${_lists.length} list${_lists.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white60,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _fetchLists,
                              child: filtered.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: groceryPagePadding(context)
                                          .add(
                                        const EdgeInsets.fromLTRB(
                                            0, 48, 0, 100),
                                      ),
                                      children: [
                                        Icon(
                                          Icons.filter_list_off_rounded,
                                          size: 56,
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.45),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No lists in this view',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Try All lists or pick a different time range.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(color: Colors.white54),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: groceryPagePadding(context)
                                          .add(
                                        const EdgeInsets.fromLTRB(
                                            0, 8, 0, 100),
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (_, i) {
                            final list = filtered[i];
                            final listId = list['id'] as String;
                            final listTitle =
                                list['title'] as String? ?? 'Untitled';
                            final stats = _listProgress[listId] ??
                                (total: 0, done: 0);
                            final progress = stats.total > 0
                                ? stats.done / stats.total
                                : 0.0;
                            final summary =
                                '${stats.total} item${stats.total == 1 ? '' : 's'}'
                                ' • ${stats.done} done';

                            Future<void> openShop() async {
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
                                      items: List<Map<String, dynamic>>.from(
                                          items),
                                      cameras: cameras,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error loading items: $e'),
                                  ),
                                );
                              }
                            }

                            return GroceryListCardShell(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Tooltip(
                                        message: 'Start grocery shopping',
                                        child: Material(
                                          color: kAccentMint
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            onTap: openShop,
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Icon(
                                                Icons.shopping_cart_rounded,
                                                size: 32,
                                                color: theme
                                                    .colorScheme.secondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onTap: () =>
                                                Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    GroceryListDetailScreen(
                                                  listId: listId,
                                                  listTitle: listTitle,
                                                ),
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 4,
                                                horizontal: 4,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    listTitle,
                                                    style: theme
                                                        .textTheme.titleLarge
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    summary,
                                                    style: theme
                                                        .textTheme.bodyMedium
                                                        ?.copyWith(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                  if (list['created_at'] !=
                                                      null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _formatDate(list[
                                                              'created_at']
                                                          as String),
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: Colors.white54,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 12),
                                                  GroceryProgressBar(
                                                    value: progress,
                                                    semanticsLabel:
                                                        'List progress',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'rename':
                                              unawaited(
                                                _renameListDialog(
                                                  listId,
                                                  listTitle,
                                                ),
                                              );
                                              break;
                                            case 'dup':
                                              unawaited(
                                                _duplicateListDialog(
                                                  listId,
                                                  listTitle,
                                                ),
                                              );
                                              break;
                                            case 'delete':
                                              unawaited(
                                                _confirmDeleteList(listId),
                                              );
                                              break;
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'rename',
                                            child: ListTile(
                                              leading: Icon(
                                                Icons.drive_file_rename_outline,
                                              ),
                                              title: Text('Rename list'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'dup',
                                            child: ListTile(
                                              leading: Icon(
                                                Icons.copy_all_outlined,
                                              ),
                                              title: Text('Duplicate list'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: Icon(
                                                Icons.delete_outline_rounded,
                                                color: theme.colorScheme.error,
                                              ),
                                              title: Text(
                                                'Delete list',
                                                style: TextStyle(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                              ),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
      ),
      floatingActionButton: Tooltip(
        message: 'New list',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kBrandPurpleMid.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton.large(
            onPressed: _showCreateDialog,
            child: const Icon(Icons.add, size: 40),
          ),
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
