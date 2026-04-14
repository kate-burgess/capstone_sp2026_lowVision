/// Shared parsing for [grocery_items] rows (quantity, etc.).
int quantityFromItemRow(Map<String, dynamic> row) {
  final q = row['quantity'];
  if (q == null) return 1;
  if (q is int) return q.clamp(1, 10);
  if (q is num) return q.toInt().clamp(1, 10);
  return 1;
}
