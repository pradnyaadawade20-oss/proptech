import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import 'auth_service.dart';
import 'google_auth.dart';

// â”€â”€ Design tokens taken from the login mock-up â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _teal = Color(0xFF15558A); // matches AppColors.primary (navy blue)
const _tealGlow = Color(0xFF2B6FA3); // matches AppColors.secondary
const _ink = Color(0xFF17202A); // matches AppColors.textPrimary
const _muted = Color(0xFF667085); // matches AppColors.textSecondary
const _fieldActiveBg = Color(0xFFEAF2FA); // matches AppColors.primaryLight
const _fieldIdleBg = Color(0xFFF1F6FC); // matches AppColors.surfaceSoft
const _fieldIdleBorder = Color(0xFFE5EAF0); // matches AppColors.border

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _googleLoading = false;

  /// false = sign in (email + password), true = create account (adds name).
  bool _createMode = false;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Accepts "98765 43210", "09876543210", "+91 98765 43210" and returns the
  /// plain 10-digit number, or null if it isn't a valid Indian mobile number.
  static String? _cleanPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? d : null;
  }

  @override
  void initState() {
    super.initState();
    for (final n in [_nameFocus, _phoneFocus, _emailFocus, _passwordFocus]) {
      n.addListener(() => setState(() {}));
    }
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _nameController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continue() async {
    final name = _nameController.text.trim();
    final phone = _cleanPhone(_phoneController.text);
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (_createMode && name.isEmpty) {
      _snack('Please enter your name');
      return;
    }
    if (_createMode && phone == null) {
      _snack('Enter a valid 10-digit mobile number');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _snack('Enter a valid email address');
      return;
    }
    if (_createMode && password.length < 8) {
      _snack('Password must be at least 8 characters');
      return;
    }
    if (password.isEmpty) {
      _snack('Enter your password');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final result = await AuthService.instance.sendOtp(
      name: name,
      phone: phone ?? '',
      email: email,
      password: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      final msg = result.errorMessage ?? 'Could not send OTP. Please try again.';
      // Backend asks for a name only when the email has no account yet.
      if (!_createMode && msg == 'Please enter your name') {
        setState(() => _createMode = true);
        _snack('No account found for this email. Add your name to create one.');
        _nameFocus.requestFocus();
        return;
      }
      _snack(msg);
      return;
    }

    context.push(
      RouteNames.otpVerification,
      extra: {
        'name': name,
        'phone': phone ?? '',
        'email': email,
        'password': password,
        'emailSent': result.emailSent.toString(),
        'skipAvailable': result.skipAvailable.toString(),
      },
    );
  }

  Future<void> _google() async {
    if (_googleLoading || _loading) return;
    if (!GoogleAuth.instance.configured) {
      _snack('Google sign-in is not set up yet (Web client ID missing)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);
    final result = await GoogleAuth.instance.signIn();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (result == null) return; // picker closed
    if (!result.success) {
      _snack(result.errorMessage ?? 'Google sign-in failed');
      return;
    }
    context.go(RouteNames.home);
  }

  @override
  Widget build(BuildContext context) {
    final emailValid = _emailRegex.hasMatch(_emailController.text.trim());
    final mq = MediaQuery.of(context);
    final keyboardOpen = mq.viewInsets.bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth;
          final height = box.maxHeight;
          final topPad = mq.padding.top;

          // Everything is scaled from the mock-up (668 px wide). The layout
          // is fitted to the screen height so it never needs to scroll.
          final heroH = width * 986 / 1595;
          final formUnits = _createMode ? 892.0 : 664.0; // mock-up px (+name, +phone in create mode)
          double s = (width / 668).clamp(0.45, 0.8).toDouble();
          double footerFactor = 1.0;
          double footerH() =>
              keyboardOpen ? 0 : width * footerFactor * _footerAspect;
          double natural() => heroH + topPad + 6 + formUnits * s + footerH();

          // With the keyboard open the page scrolls, so keep normal sizes.
          if (!keyboardOpen && natural() > height) footerFactor = 0.72;
          if (!keyboardOpen && natural() > height) {
            s = ((height - heroH - topPad - 6 - footerH()) / formUnits)
                .clamp(0.4, s)
                .toDouble();
          }
          final gapX = 52 * (width / 668).clamp(0.45, 0.8).toDouble();
          // Spare height (tall phones) is shared with the gap under the hero.
          final extra = math.max(0.0, height - natural());
          final contentH = math.max(height, natural());

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // Only scrolls when the keyboard is covering part of the form.
            physics: keyboardOpen
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: keyboardOpen ? null : contentH,
              child: Column(
                mainAxisSize:
                    keyboardOpen ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  // Hero banner (logo, headline, house, wave are in the image).
                  // It starts below the status bar; the strip behind the
                  // status bar uses the sky colours and the image fades in.
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFCFE5F3),
                          Color(0xFFD2E4F4),
                          Color(0xFF91CBF1),
                          Color(0xFF7EBEED),
                        ],
                        stops: [0.0, 0.33, 0.66, 1.0],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: topPad + 6),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                          stops: [0.0, 0.07],
                        ).createShader(rect),
                        child: Image.asset(
                          'assets/images/login_hero.jpg',
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(gapX, 62 * s + extra * 0.3, gapX, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _createMode
                              ? Padding(
                                  padding: EdgeInsets.only(bottom: 31 * s),
                                  child: Column(
                                    children: [
                                      _Field(
                                        s: s,
                                        label: 'Full name',
                                        controller: _nameController,
                                        focusNode: _nameFocus,
                                        icon: Icons.person_outline_rounded,
                                        highlighted: _nameFocus.hasFocus,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.name
                                        ],
                                      ),
                                      SizedBox(height: 31 * s),
                                      _Field(
                                        s: s,
                                        label: 'Mobile number (10 digits)',
                                        controller: _phoneController,
                                        focusNode: _phoneFocus,
                                        icon: Icons.phone_outlined,
                                        highlighted: _phoneFocus.hasFocus,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.telephoneNumber
                                        ],
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[0-9+ ]')),
                                          LengthLimitingTextInputFormatter(16),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        _Field(
                          s: s,
                          label: 'Email address',
                          controller: _emailController,
                          focusNode: _emailFocus,
                          icon: Icons.mail_outline_rounded,
                          highlighted: _emailFocus.hasFocus || emailValid,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          suffix: emailValid
                              ? Icon(Icons.check_circle_rounded,
                                  color: _teal, size: 34 * s)
                              : null,
                        ),
                        SizedBox(height: 31 * s),
                        _Field(
                          s: s,
                          label: 'Password',
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          icon: Icons.lock_outline_rounded,
                          highlighted: _passwordFocus.hasFocus,
                          obscure: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _continue(),
                          suffix: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: _muted,
                                size: 38 * s,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 72 * s,
                          child: Align(
                            alignment: const Alignment(1, -0.14),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.push(
                                  RouteNames.forgotPassword,
                                  extra: _emailController.text.trim()),
                              child: Text(
                                'Forgot password?',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: _t(s, 17),
                                  fontWeight: FontWeight.w600,
                                  color: _teal,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _teal,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _ContinueButton(
                            s: s, loading: _loading, onTap: _continue),
                        SizedBox(height: 42 * s),
                        _OrDivider(s: s),
                        SizedBox(height: 23 * s),
                        _GoogleButton(
                          s: s,
                          loading: _googleLoading,
                          onTap: _google,
                        ),
                        SizedBox(height: 45 * s),
                        Text(
                          _createMode
                              ? 'Already have an account?'
                              : 'Don\u2019t have an account?',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: _t(s, 16),
                            color: _muted,
                          ),
                        ),
                        SizedBox(height: 5 * s),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              setState(() => _createMode = !_createMode),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 6 * s),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _createMode ? 'Sign in' : 'Create account',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: _t(s, 18.5),
                                    fontWeight: FontWeight.w700,
                                    color: _teal,
                                  ),
                                ),
                                SizedBox(width: 10 * s),
                                Icon(Icons.arrow_forward_rounded,
                                    color: _teal, size: 26 * s),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Takes whatever height is left, so it can never overflow.
                  if (!keyboardOpen)
                    Expanded(child: _Footer(s: s, factor: footerFactor)),
                  if (keyboardOpen) const SizedBox(height: 16),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Footer asset (cropped) height / width.
const double _footerAspect = 386 / 900;

/// Font size scaled from the mock-up, kept readable on small phones.
double _t(double s, double px) => math.max(px * s * 1.18, 11.5);

// â”€â”€ Input field with floating label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _Field extends StatelessWidget {
  final double s;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final IconData icon;
  final bool highlighted;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.s,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.icon,
    required this.highlighted,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: math.max(83 * s, 46),
      padding: EdgeInsets.only(left: 25 * s, right: 26 * s),
      decoration: BoxDecoration(
        color: highlighted ? _fieldActiveBg : _fieldIdleBg,
        borderRadius: BorderRadius.circular(22 * s),
        border: Border.all(
          color: highlighted ? _teal.withValues(alpha: 0.75) : _fieldIdleBorder,
          width: highlighted ? 1.3 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: highlighted ? _ink : _muted, size: 38 * s),
          SizedBox(width: 24 * s),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              obscuringCharacter: '\u2022',
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              onSubmitted: onSubmitted,
              inputFormatters: inputFormatters,
              cursorColor: _teal,
              style: GoogleFonts.plusJakartaSans(
                fontSize: _t(s, 20),
                fontWeight: FontWeight.w500,
                color: _ink,
                letterSpacing: obscure ? 1.2 : 0,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                labelText: label,
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: _t(s, 19),
                  color: _muted,
                ),
                floatingLabelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: _t(s, 16.5),
                  color: _muted,
                ),
              ),
            ),
          ),
          if (suffix != null) ...[SizedBox(width: 10 * s), suffix!],
        ],
      ),
    );
  }
}

// â”€â”€ Continue button with glow and sparkle ticks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ContinueButton extends StatelessWidget {
  final double s;
  final bool loading;
  final VoidCallback onTap;
  const _ContinueButton(
      {required this.s, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = 22 * s;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: math.max(74 * s, 44),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            boxShadow: [
              BoxShadow(
                color: _teal.withValues(alpha: 0.30),
                blurRadius: 26 * s,
                offset: Offset(0, 14 * s),
              ),
            ],
            gradient: const RadialGradient(
              center: Alignment(0.05, 0.1),
              radius: 1.1,
              colors: [_tealGlow, _teal],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(r),
              onTap: loading ? null : onTap,
              child: Center(
                child: loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Continue',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: _t(s, 23),
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 14 * s),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 30 * s),
                        ],
                      ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -22 * s,
          top: -26 * s,
          child: IgnorePointer(
            child: CustomPaint(
              size: Size(28 * s, 28 * s),
              painter: _SparklePainter(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final p = Paint()
      ..color = _teal
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(3 * k, 4 * k), Offset(5 * k, 11 * k), p);
    canvas.drawLine(Offset(11 * k, 2 * k), Offset(17 * k, 8 * k), p);
    canvas.drawLine(Offset(15 * k, 15 * k), Offset(22 * k, 17 * k), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// â”€â”€ OR divider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OrDivider extends StatelessWidget {
  final double s;
  const _OrDivider({required this.s});

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: Divider(height: 1, thickness: 1, color: Color(0xFFE5EAF0)),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 22 * s),
          child: Text(
            'OR',
            style: GoogleFonts.plusJakartaSans(
              fontSize: _t(s, 16),
              color: _muted,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

// â”€â”€ Continue with Google â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GoogleButton extends StatelessWidget {
  final double s;
  final bool loading;
  final VoidCallback onTap;
  const _GoogleButton(
      {required this.s, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final r = 22 * s;
    return Material(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(r),
      child: InkWell(
        borderRadius: BorderRadius.circular(r),
        onTap: loading ? null : onTap,
        child: Container(
          height: math.max(69 * s, 42),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: const Color(0xFFE5EAF0)),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: _teal),
                  ),
                )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: Size(36 * s, 36 * s),
                painter: _GoogleGPainter(),
              ),
              SizedBox(width: 18 * s),
              Text(
                'Continue with Google',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: _t(s, 21),
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-colour Google "G" drawn with arcs (no image / package needed).
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.21;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: s / 2 - stroke / 2,
    );
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);
    const blue = Color(0xFF4285F4);
    double rad(double d) => d * math.pi / 180;

    // Clockwise from 3 o'clock: blue -> green -> yellow -> red.
    canvas.drawArc(rect, rad(0), rad(55), false, arc(blue));
    canvas.drawArc(rect, rad(55), rad(90), false, arc(green));
    canvas.drawArc(rect, rad(145), rad(70), false, arc(yellow));
    canvas.drawArc(rect, rad(215), rad(100), false, arc(red));
    // Blue crossbar
    canvas.drawRect(
      Rect.fromLTWH(s * 0.5, s * 0.42, s * 0.47, stroke * 0.95),
      Paint()..color = blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// â”€â”€ Bottom illustration (full width, soft 3D depth) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _Footer extends StatelessWidget {
  final double s;
  final double factor;
  const _Footer({required this.s, required this.factor});

  static const _asset = 'assets/images/login_footer.png';

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      // Never taller than the space left; crops the empty sky on top
      // instead of overflowing.
      final h = math.min(w * factor * _footerAspect, box.maxHeight);
      if (h < 8) return const SizedBox.shrink();

      Widget img({Color? tint}) => Image.asset(
            _asset,
            width: w,
            height: h,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.high,
            color: tint,
            colorBlendMode: tint == null ? null : BlendMode.srcIn,
          );

      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Ground shadow: blurred dark-teal copy pushed down/right.
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(w * 0.012, h * 0.035),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Opacity(
                      opacity: 0.35,
                      child: img(tint: const Color(0xFF15558A)),
                    ),
                  ),
                ),
              ),
              // Main illustration: tilted slightly back for a 3D feel.
              Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(0.10),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.92, 0, 0, 0, 0,
                    0, 0.94, 0, 0, 0,
                    0, 0, 0.93, 0, 0,
                    0, 0, 0, 1.15, 0,
                  ]),
                  child: img(),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}