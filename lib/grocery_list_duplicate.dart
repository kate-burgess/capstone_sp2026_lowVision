import 'grocery_item_fields.dart';
import 'main.dart';

/// Creates a new list with [newTitle], copies all items with [is_checked] false
/// and the same [quantity] / [category] / [name]. Returns the new list id.
Future<String> duplicateGroceryList({
  required String sourceListId,
  required String newTitle,
}) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not logged in');

  final created = await supabase
      .from('grocery_lists')
      .insert({'user_id': userId, 'title': newTitle}).select().single();

  final newId = created['id'] as String;
  final rows = await supabase
      .from('grocery_items')
      .select()
      .eq('list_id', sourceListId);

  for (final raw in List<Map<String, dynamic>>.from(rows)) {
    await supabase.from('grocery_items').insert({
      'list_id': newId,
      'user_id': userId,
      'name': raw['name'],
      'category': raw['category'],
      'is_checked': false,
      'quantity': quantityFromItemRow(raw),
    });
  }
  return newId;
}
