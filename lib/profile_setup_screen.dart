import 'package:flutter/material.dart';
import 'main.dart';
import 'grocery_list_screen.dart';

/// Used both for initial profile setup (after signup) and for editing an
/// existing profile. Pass isEditing: true when opening from settings.
class ProfileSetupScreen extends StatefulWidget {
  final bool isEditing;
  const ProfileSetupScreen({super.key, this.isEditing = false});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _dietOptions = [
    'No restrictions',
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Dairy-Free',
    'Halal',
    'Kosher',
    'Low-Sodium',
    'Low-Sugar',
  ];

  static const _allergyOptions = [
    'None',
    'Peanuts',
    'Tree Nuts',
    'Shellfish',
    'Fish',
    'Dairy',
    'Eggs',
    'Soy',
    'Wheat / Gluten',
  ];

  final Set<String> _selectedDiet = {};
  final Set<String> _selectedAllergies = {};

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final profile = rows.first as Map<String, dynamic>;

        _nameController.text = profile['full_name'] as String? ?? '';

        final dietRaw = profile['dietary_preferences'] as String? ?? '';
        for (final part in dietRaw.split(',')) {
          final trimmed = part.trim();
          if (_dietOptions.contains(trimmed)) _selectedDiet.add(trimmed);
        }

        final allergyRaw = profile['allergies'] as String? ?? '';
        for (final part in allergyRaw.split(',')) {
          final trimmed = part.trim();
          if (_allergyOptions.contains(trimmed)) _selectedAllergies.add(trimmed);
        }
      }
    } catch (_) {
      // Silently ignore — the user can still fill in the form.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in.');

      final dietText = _selectedDiet.isEmpty
          ? 'No restrictions'
          : _selectedDiet.join(', ');
      final allergyText = _selectedAllergies.isEmpty
          ? 'None'
          : _selectedAllergies.join(', ');

      await supabase.from('user_profiles').upsert({
        'id': userId,
        'full_name': name,
        'dietary_preferences': dietText,
        'allergies': allergyText,
      });

      if (!mounted) return;

      if (widget.isEditing) {
        // Return to the previous screen with a success message.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GroceryListScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            title: Text(widget.isEditing ? 'Edit profile' : 'Set up your profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit profile' : 'Set up your profile'),
        leading: widget.isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEditing ? 'Update your profile' : 'Tell us about yourself',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This helps personalise your grocery lists.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Full name
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 28),

                // Dietary preferences
                const Text(
                  'Dietary preferences',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text('Select all that apply',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _dietOptions.map((opt) {
                    final selected = _selectedDiet.contains(opt);
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          if (opt == 'No restrictions') _selectedDiet.clear();
                          else _selectedDiet.remove('No restrictions');
                          _selectedDiet.add(opt);
                        } else {
                          _selectedDiet.remove(opt);
                        }
                      }),
                      selectedColor:
                          Theme.of(context).colorScheme.primaryContainer,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // Allergies
                const Text(
                  'Allergies',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text('Select all that apply',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _allergyOptions.map((opt) {
                    final selected = _selectedAllergies.contains(opt);
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          if (opt == 'None') _selectedAllergies.clear();
                          else _selectedAllergies.remove('None');
                          _selectedAllergies.add(opt);
                        } else {
                          _selectedAllergies.remove(opt);
                        }
                      }),
                      selectedColor: Colors.red.shade100,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                if (_error != null) ...[
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            widget.isEditing ? 'Save changes' : 'Save and continue',
                            style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),

                if (!widget.isEditing)
                  Center(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (_) => const GroceryListScreen()),
                              ),
                      child: const Text('Skip for now'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
