/// Hides a phone number like job portals do: only the country code stays
/// visible, every other digit becomes a star.
///   +917304245301  ->  +91 **********
///   7304245301     ->  +91 **********
String maskPhone(String phone, {String defaultCode = '91'}) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.length > 10) {
    final code = digits.substring(0, digits.length - 10);
    return '+$code ${'*' * 10}';
  }
  return '+$defaultCode ${'*' * digits.length}';
}


/// Hides an email: first letter + stars + the domain.
///   shubham123@gmail.com  ->  s*********@gmail.com
String maskEmail(String email) {
  final e = email.trim();
  final at = e.indexOf('@');
  if (at <= 0) return e.isEmpty ? '' : '*' * e.length;
  final local = e.substring(0, at);
  return '${local[0]}${'*' * (local.length > 1 ? local.length - 1 : 1)}${e.substring(at)}';
}