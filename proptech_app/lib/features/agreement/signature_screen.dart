import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import 'agreement.dart';

/// Signature capture screen — user picks Draw or Type, no OTP.
/// Returns a Map {signatureType, signatureData} via Navigator.pop on submit.
class SignatureScreen extends StatefulWidget {
  final String agreementId;
  final String signerName;

  const SignatureScreen({
    super.key,
    required this.agreementId,
    required this.signerName,
  });

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  SignatureType _mode = SignatureType.draw;

  // --- draw mode state ---
  final GlobalKey _canvasKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;

  // --- type mode state ---
  final TextEditingController _typedController = TextEditingController();

  bool get _hasContent =>
      _mode == SignatureType.draw ? _strokes.isNotEmpty : _typedController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _typedController.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = null;
      _typedController.clear();
    });
  }

  Future<String> _captureDrawnSignature() async {
    final boundary = _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return base64Encode(bytes);
  }

  Future<void> _submit() async {
    if (!_hasContent) return;

    String signatureData;
    if (_mode == SignatureType.draw) {
      signatureData = await _captureDrawnSignature();
    } else {
      signatureData = _typedController.text.trim();
    }

    if (!mounted) return;
    Navigator.of(context).pop({
      'signatureType': _mode.apiValue,
      'signatureData': signatureData,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Sign Agreement',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Signing as ${widget.signerName}',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _buildModeToggle(),
              const SizedBox(height: 20),
              Expanded(
                child: _mode == SignatureType.draw ? _buildDrawPad() : _buildTypePad(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _hasContent ? _clear : null,
                    child: Text(
                      'Clear',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Confirm & Sign',
                onPressed: _hasContent ? _submit : null,
              ),
              const SizedBox(height: 8),
              Text(
                'By signing, you agree this represents your legal signature on this document.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildToggleTab('Draw', SignatureType.draw),
          _buildToggleTab('Type', SignatureType.type),
        ],
      ),
    );
  }

  Widget _buildToggleTab(String label, SignatureType type) {
    final selected = _mode == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawPad() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            RepaintBoundary(
              key: _canvasKey,
              child: Container(
                color: Colors.white,
                width: double.infinity,
                height: double.infinity,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentStroke = [details.localPosition];
                      _strokes.add(_currentStroke!);
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _currentStroke!.add(details.localPosition);
                    });
                  },
                  onPanEnd: (_) => _currentStroke = null,
                  child: CustomPaint(
                    painter: _SignaturePainter(_strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            if (_strokes.isEmpty)
              IgnorePointer(
                child: Center(
                  child: Text(
                    'Sign here with your finger',
                    style: GoogleFonts.inter(color: AppColors.textHint, fontSize: 14),
                  ),
                ),
              ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Container(height: 1, color: AppColors.border),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypePad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type your full name',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _typedController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g. ${widget.signerName}',
            filled: true,
            fillColor: AppColors.surface,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Preview',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              _typedController.text.trim().isEmpty ? '' : _typedController.text.trim(),
              style: GoogleFonts.dancingScript(
                fontSize: 42,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}