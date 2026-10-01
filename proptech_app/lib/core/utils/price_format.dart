/// One place that decides how a price is shown across the whole app
/// (Home, Search, cards, detail screen, My Properties ...), so the same
/// listing never shows "₹5.0Cr" in one screen and "₹50000000" in another.
///
///   50000000  -> ₹5 Cr
///   15000000  -> ₹1.5 Cr
///   5000000   -> ₹50 L
///   250000    -> ₹2.5 L
///   25000     -> ₹25,000
String formatPrice(double v, [String unit = '']) {
  String trim(double x) {
    final s = x.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  final String s;
  if (v >= 10000000) {
    s = '₹${trim(v / 10000000)} Cr';
  } else if (v >= 100000) {
    s = '₹${trim(v / 100000)} L';
  } else {
    s = '₹${_indianGrouping(v.round())}';
  }
  return '$s$unit';
}

String _indianGrouping(int n) {
  final digits = n.toString();
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}