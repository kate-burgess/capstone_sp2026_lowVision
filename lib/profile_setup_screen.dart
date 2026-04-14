import 'package:flutter/material.dart';

import 'grocery_list_screen.dart';
import 'grocery_ui.dart';
import 'main.dart';

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

      final list = rows as List<dynamic>;
      if (list.isNotEmpty) {
        final profile = Map<String, dynamic>.from(list.first as Map);

        _nameController.text = profile['full_name'] as String? ?? '';

        final dietRaw = profile['dietary_preferences'] as String? ?? '';
        for (final part in dietRaw.split(',')) {
          final trimmed = part.trim();
          if (_dietOptions.contains(trimmed)) _selectedDiet.add(trimmed);
        }

        final allergyRaw = profile['allergies'] as String? ?? '';
        for (final part in allergyRaw.split(',')) {
          final trimmed = part.trim();
          if (_allergyOptions.contains(trimmed)) {
            _selectedAllergies.add(trimmed);
          }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated!',
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF232733),
              ),
            ),
            backgroundColor: const Color(0xFF3AE4C2),
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
          title: Text(
            widget.isEditing ? 'Edit profile' : 'Set up your profile',
          ),
        ),
        body: GroceryAmbientBackdrop(
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Profile' : 'Set Up Your Profile'),
        leading: widget.isEditing
            ? IconButton(
                tooltip: 'Go back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: groceryPagePadding(context).add(
                  const EdgeInsets.symmetric(vertical: 24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const GroceryProfilePersonBadge(size: 76),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isEditing
                                    ? 'Edit Profile'
                                    : 'Profile Setup',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Help us personalize your experience',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'Enter your name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      style: theme.textTheme.bodyLarge,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Dietary preferences',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select all that apply',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: _dietOptions.map((opt) {
                        final selected = _selectedDiet.contains(opt);
                        return FilterChip(
                          label: Text(opt),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              if (opt == 'No restrictions') {
                                _selectedDiet.clear();
                              } else {
                                _selectedDiet.remove('No restrictions');
                              }
                              _selectedDiet.add(opt);
                            } else {
                              _selectedDiet.remove(opt);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    Text('Allergies', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Select all that apply',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: _allergyOptions.map((opt) {
                        final selected = _selectedAllergies.contains(opt);
                        return FilterChip(
                          label: Text(opt),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              if (opt == 'None') {
                                _selectedAllergies.clear();
                              } else {
                                _selectedAllergies.remove('None');
                              }
                              _selectedAllergies.add(opt);
                            } else {
                              _selectedAllergies.remove(opt);
                            }
                          }),
                          selectedColor:
                              theme.colorScheme.error.withValues(alpha: 0.3),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    GroceryGlowButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              widget.isEditing
                                  ? 'Save Changes'
                                  : 'Save & Continue',
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (!widget.isEditing)
                      Center(
                        child: TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const GroceryListScreen(),
                                    ),
                                  ),
                          style: TextButton.styleFrom(
                            textStyle: theme.textTheme.bodyMedium,
                          ),
                          child: const Text('Skip for now'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
