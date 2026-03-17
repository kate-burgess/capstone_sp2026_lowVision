import 'package:flutter/material.dart';

import 'main.dart';
import 'grocery_list_detail_screen.dart';
import 'supabase_auth_screen.dart';
import 'take_picture_screen.dart';
import 'aisle_scanner_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchLists();
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
        SnackBar(content: Text('Error creating list: $e'), backgroundColor: Colors.red),
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
        SnackBar(content: Text('Error deleting list: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New grocery list'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List title'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grocery Lists'),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ProfileSetupScreen(isEditing: true)),
            ),
          ),
          IconButton(
            tooltip: 'Go to camera / OCR',
            icon: const Icon(Icons.camera_alt),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TakePictureScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _fetchLists,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _lists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_cart_outlined, size: 72, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No lists yet.\nTap + to create your first grocery list.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchLists,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lists.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final list = _lists[i];
                          final listId = list['id'] as String;
                          final listTitle = list['title'] as String? ?? 'Untitled';
                          return ListTile(
                            leading: const Icon(Icons.list_alt),
                            title: Text(listTitle),
                            subtitle: list['created_at'] != null
                                ? Text(
                                    _formatDate(list['created_at'] as String),
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Start guided shopping mode for this list
                                IconButton(
                                  tooltip: 'Start shopping',
                                  icon: const Icon(Icons.shopping_cart,
                                      color: Colors.deepPurple),
                                  onPressed: () async {
                                    // Fetch items for this list then open aisle scanner
                                    try {
                                      final items = await supabase
                                          .from('grocery_items')
                                          .select()
                                          .eq('list_id', listId)
                                          .order('name');
                                      if (!context.mounted) return;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AisleScannerScreen(
                                            listId: listId,
                                            listTitle: listTitle,
                                            items: List<Map<String, dynamic>>.from(items),
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text('Error loading items: $e'),
                                            backgroundColor: Colors.red),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _deleteList(listId),
                                ),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroceryListDetailScreen(
                                  listId: listId,
                                  listTitle: listTitle,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        tooltip: 'New list',
        child: const Icon(Icons.add),
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
