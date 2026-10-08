import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/api/token_store.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

const _rooms = ['Living Room', 'Bedroom', 'Kitchen', 'Bathroom', 'Balcony', 'Other'];

/// Move-in vs move-out photos, room by room (the evidence behind deposit deductions).
class LeasePhotosTab extends StatefulWidget {
  final Lease lease;
  final String role;
  final Future<void> Function() onChanged;
  const LeasePhotosTab({super.key, required this.lease, required this.role, required this.onChanged});

  @override
  State<LeasePhotosTab> createState() => _LeasePhotosTabState();
}

class _LeasePhotosTabState extends State<LeasePhotosTab> {
  late final Future<List<RoomComparison>> _future = LeaseService.instance.comparison(widget.lease.id);
  String? _myId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    TokenStore.instance.getUserId().then((v) {
      if (mounted) setState(() => _myId = v);
    });
  }

  Lease get _l => widget.lease;

  bool get _moveInOpen => _l.status == 'active' && _l.moveInConfirmedAt == null;

  bool get _moveOutOpen =>
      (_l.status == 'notice_given' || _l.status == 'moved_out') &&
      !const {'settlement', 'disputed', 'refund_due', 'refunded'}.contains(_l.depositStatus);

  Future<void> _upload(String kind) async {
    final r = await showModalBottomSheet<_UploadInput>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UploadSheet(kind: kind),
    );
    if (r == null) return;
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => LeaseService.instance.uploadPhotos(_l.id, kind: kind, room: r.room, caption: r.caption, files: r.files),
      success: 'Photos added',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await widget.onChanged();
  }

  void _onDelete(LeasePhoto p) {
    if (p.uploaderId == _myId) {
      _delete(p);
    } else {
      snack(context, 'You can only delete photos you uploaded', error: true);
    }
  }

  Future<void> _delete(LeasePhoto p) async {
    if (!await confirmDialog(context, 'Delete photo', 'Delete this photo?', yes: 'Delete')) return;
    if (!mounted) return;
    if (await runGuarded(context, () => LeaseService.instance.deletePhoto(_l.id, p.id), success: 'Photo deleted')) {
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomComparison>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
        final rooms = snap.data ?? [];
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const InfoBanner(
                'Photos taken at move-in and move-out are the proof used for any deposit deduction. Add clear photos of every room.',
                icon: Icons.photo_camera_outlined,
              ),
              if (_busy) const LinearProgressIndicator(),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_moveInOpen && !_busy) ? () => _upload('move_in') : null,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Move-in'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_moveOutOpen && !_busy) ? () => _upload('move_out') : null,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Move-out'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                _l.moveInConfirmedAt != null
                    ? 'Move-in photos are locked (confirmed by the tenant). Move-out photos open after notice is given.'
                    : 'Move-in photos lock once the tenant confirms the move-in condition.',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (rooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No photos yet.', style: GoogleFonts.inter(color: AppColors.textSecondary))),
                ),
              ...rooms.map((r) => SectionCard(
                    title: r.room,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Move-in', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      PhotoStrip(
                        r.moveIn,
                        canDelete: _moveInOpen,
                        onDelete: _onDelete,
                      ),
                      const SizedBox(height: 12),
                      Text('Move-out', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      PhotoStrip(
                        r.moveOut,
                        canDelete: _moveOutOpen,
                        onDelete: _onDelete,
                      ),
                    ]),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _UploadInput {
  final String room, caption;
  final List<XFile> files;
  _UploadInput(this.room, this.caption, this.files);
}

class _UploadSheet extends StatefulWidget {
  final String kind;
  const _UploadSheet({required this.kind});

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  String _room = _rooms.first;
  final _caption = TextEditingController();
  final List<XFile> _files = [];

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _gallery() async {
    final f = await ImagePicker().pickMultiImage(limit: 10);
    if (f.isNotEmpty) setState(() => _files..clear()..addAll(f.take(10)));
  }

  Future<void> _camera() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (f != null) setState(() => _files.add(f));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.kind == 'move_in' ? 'move-in' : 'move-out';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add $label photos', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _rooms
                .map((r) => ChoiceChip(label: Text(r), selected: _room == r, onSelected: (_) => setState(() => _room = r)))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(controller: _caption, maxLength: 200, decoration: const InputDecoration(labelText: 'Caption (optional)')),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _camera, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Camera'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _gallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery'))),
          ]),
          if (_files.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_files.length} photo(s) selected')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _files.isEmpty ? null : () => Navigator.pop(context, _UploadInput(_room, _caption.text.trim(), List.of(_files))),
              child: const Text('Upload'),
            ),
          ),
        ]),
      ),
    );
  }
}