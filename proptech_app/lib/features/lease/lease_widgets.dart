import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/api/token_store.dart';
import 'lease_models.dart';
import 'lease_service.dart';

// ---------------------------------------------------------------- formatting

/// ₹1,25,000 (Indian grouping, paise only when present).
String inr(double v) {
  final neg = v < 0;
  v = v.abs();
  var whole = v.truncate();
  var paise = ((v - whole) * 100).round();
  if (paise == 100) {
    whole += 1;
    paise = 0;
  }
  final s = whole.toString();
  String g;
  if (s.length <= 3) {
    g = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    g = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$g${paise > 0 ? '.${paise.toString().padLeft(2, '0')}' : ''}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String fmtDate(String? s) {
  if (s == null || s.isEmpty) return '-';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String fmtDateTime(DateTime? d) {
  if (d == null) return '';
  return '${d.day} ${_months[d.month - 1]} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String prettify(String s) {
  if (s.isEmpty) return '-';
  final t = s.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}

Color statusColor(String s) {
  switch (s) {
    case 'paid':
    case 'held':
    case 'refunded':
    case 'active':
    case 'renew_accepted':
    case 'renewed':
      return AppColors.success;
    case 'overdue':
    case 'disputed':
    case 'renew_declined':
      return AppColors.error;
    case 'submitted':
    case 'pending':
    case 'inspection':
    case 'settlement':
    case 'refund_due':
    case 'notice_given':
    case 'renew_requested':
    case 'vacate':
      return AppColors.warning;
    default:
      return AppColors.textSecondary;
  }
}

// ------------------------------------------------------------------ feedback

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null));
}

/// Runs [action]; shows the server's error message on failure. Returns true on success.
Future<bool> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) snack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String yes = 'Yes'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  required String hint,
  int minLength = 3,
  String button = 'Submit',
  TextInputType keyboard = TextInputType.text,
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        maxLines: keyboard == TextInputType.multiline ? 3 : 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (c.text.trim().length < minLength) return;
            Navigator.pop(context, c.text.trim());
          },
          child: Text(button),
        ),
      ],
    ),
  );
}

Future<String?> askDate(BuildContext context, {required DateTime first, required DateTime last, DateTime? initial}) async {
  var init = initial ?? first;
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;
  final d = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
  return d == null ? null : ymd(d);
}

// ------------------------------------------------------------ payment sheet

const paymentMethods = {
  'upi': 'UPI',
  'bank_transfer': 'Bank transfer',
  'cash': 'Cash',
  'cheque': 'Cheque',
  'other': 'Other',
};

typedef PaymentInput = ({String method, String reference});

Future<PaymentInput?> askPayment(
  BuildContext context, {
  required String title,
  required String subtitle,
  String button = 'Submit',
}) {
  return showModalBottomSheet<PaymentInput>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PaymentSheet(title: title, subtitle: subtitle, button: button),
  );
}

class _PaymentSheet extends StatefulWidget {
  final String title, subtitle, button;
  const _PaymentSheet({required this.title, required this.subtitle, required this.button});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String _method = 'upi';
  final _ref = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  void _submit() {
    final ref = _ref.text.trim();
    if (_method != 'cash' && ref.isEmpty) {
      setState(() => _error = 'Enter the transaction / reference number');
      return;
    }
    Navigator.pop(context, (method: _method, reference: ref));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(widget.subtitle, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: paymentMethods.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _method == e.key,
                      onSelected: (_) => setState(() {
                        _method = e.key;
                        _error = null;
                      }),
                    ))
                .toList(),
          ),
          if (_method != 'cash') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              decoration: InputDecoration(
                labelText: _method == 'cheque' ? 'Cheque number' : 'Transaction / reference number',
                errorText: _error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _submit, child: Text(widget.button)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- layout

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill(this.label, this.color, {super.key});

  factory StatusPill.status(String status) => StatusPill(prettify(status), statusColor(status));

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text(title!, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600))),
                  if (trailing != null) trailing!,
                ]),
              ),
            child,
          ],
        ),
      );
}

class InfoRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13))),
            Expanded(
              flex: 5,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
            ),
          ],
        ),
      );
}

class InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const InfoBanner(this.text, {super.key, this.color = AppColors.primary, this.icon = Icons.info_outline});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
}

// ------------------------------------------------------------------- photos

/// Lease photos are private (need the login token), so a plain Image.network won't work.
class LeasePhotoImage extends StatefulWidget {
  final LeasePhoto photo;
  final double? width, height;
  final BoxFit fit;
  const LeasePhotoImage(this.photo, {super.key, this.width, this.height, this.fit = BoxFit.cover});

  @override
  State<LeasePhotoImage> createState() => _LeasePhotoImageState();
}

class _LeasePhotoImageState extends State<LeasePhotoImage> {
  late final Future<String?> _token = TokenStore.instance.getToken();

  @override
  Widget build(BuildContext context) {
    final ph = Container(width: widget.width, height: widget.height, color: AppColors.divider);
    return FutureBuilder<String?>(
      future: _token,
      builder: (_, snap) {
        if (!snap.hasData) return ph;
        final url = widget.photo.url.startsWith('http')
            ? widget.photo.url
            : '${LeaseService.instance.baseUrl}${widget.photo.url}';
        return CachedNetworkImage(
          imageUrl: url,
          httpHeaders: {'Authorization': 'Bearer ${snap.data}'},
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          placeholder: (_, __) => ph,
          errorWidget: (_, __, ___) => Container(
            width: widget.width,
            height: widget.height,
            color: AppColors.divider,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textHint),
          ),
        );
      },
    );
  }
}

void showPhotoViewer(BuildContext context, LeasePhoto photo) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: InteractiveViewer(child: LeasePhotoImage(photo, fit: BoxFit.contain))),
          if (photo.caption.isNotEmpty || photo.uploaderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                [photo.room, photo.caption, if (photo.uploaderName.isNotEmpty) 'by ${photo.uploaderName}']
                    .where((e) => e.isNotEmpty)
                    .join(' • '),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
}

class PhotoStrip extends StatelessWidget {
  final List<LeasePhoto> photos;
  final bool canDelete;
  final void Function(LeasePhoto)? onDelete;
  const PhotoStrip(this.photos, {super.key, this.canDelete = false, this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Text('No photos', style: GoogleFonts.inter(color: AppColors.textHint, fontSize: 12));
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = photos[i];
          return GestureDetector(
            onTap: () => showPhotoViewer(context, p),
            child: Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LeasePhotoImage(p, width: 84, height: 84)),
              if (canDelete && onDelete != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onDelete!(p),
                    child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12, color: Colors.white)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}