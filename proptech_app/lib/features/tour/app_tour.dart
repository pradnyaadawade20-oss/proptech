import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Remembers whether the user has already seen the guided tour, and lets
/// other screens (e.g. Profile) ask Home to replay it.
class AppTourStore {
  AppTourStore._();
  static final AppTourStore instance = AppTourStore._();

  static const _seenKey = 'app_tour_seen_v1';

  /// Incremented whenever someone wants the tour to start again.
  final ValueNotifier<int> replayTick = ValueNotifier<int>(0);

  Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      return true; // if storage fails, never nag the user
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  void requestReplay() => replayTick.value++;
}

/// Keys for widgets that live outside HomeScreen but are part of the tour.
class AppTourKeys {
  AppTourKeys._();
  static final GlobalKey bottomNav = GlobalKey(debugLabel: 'tour_bottom_nav');
}

/// One step of the tour. Provide either [targetKey] (highlights that widget),
/// or [rectBuilder] (custom highlight area), or neither (centered welcome card).
class AppTourStep {
  final GlobalKey? targetKey;
  final Rect? Function()? rectBuilder;
  final IconData icon;
  final String title;
  final String description;

  /// Extra breathing room around the highlighted widget.
  final double padding;

  const AppTourStep({
    this.targetKey,
    this.rectBuilder,
    required this.icon,
    required this.title,
    required this.description,
    this.padding = 6,
  });
}

class AppTour {
  AppTour._();
  static OverlayEntry? _entry;

  static bool get isRunning => _entry != null;

  /// Shows the spotlight tour on top of the current screen.
  static void start(
    BuildContext context,
    List<AppTourStep> steps, {
    VoidCallback? onFinished,
  }) {
    if (_entry != null || steps.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      entry.remove();
      _entry = null;
      AppTourStore.instance.markSeen();
      onFinished?.call();
    }

    entry = OverlayEntry(
      builder: (_) => _TourOverlay(steps: steps, onClose: close),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _TourOverlay extends StatefulWidget {
  final List<AppTourStep> steps;
  final VoidCallback onClose;
  const _TourOverlay({required this.steps, required this.onClose});

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  int _index = 0;

  /// Global rect of the thing being highlighted. null => centered welcome card.
  Rect? _target;

  /// True while we scroll to / measure the next target. The card is hidden
  /// during this short window so it never jumps around.
  bool _measuring = true;

  /// Guards against stale async work when the user taps Next quickly.
  int _token = 0;

  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  AppTourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStep());
  }

  @override
  void dispose() {
    _fade.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _showStep() async {
    final token = ++_token;
    final step = _step;
    if (mounted) setState(() => _measuring = true);

    // Bring the target on screen first (it may be further down the home list).
    final ctx = step.targetKey?.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    }

    // Wait for layout to settle; retry a few frames, then fall back to a
    // centered card so the tour can never get stuck on a blank dim screen.
    Rect? rect;
    for (var i = 0; i < 10; i++) {
      if (!mounted || token != _token) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != _token) return;
      rect = _measure(step);
      if (rect != null) break;
      if (step.targetKey == null && step.rectBuilder == null) break; // welcome step
    }
    if (!mounted || token != _token) return;
    setState(() {
      _target = rect;
      _measuring = false;
    });
  }

  Rect? _measure(AppTourStep step) {
    Rect? raw;
    if (step.rectBuilder != null) {
      raw = step.rectBuilder!();
    } else {
      final box = step.targetKey?.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        raw = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    if (raw == null) return null;
    final screen = Offset.zero & MediaQuery.of(context).size;
    final visible = raw.intersect(screen);
    if (visible.width <= 0 || visible.height <= 0) return null;
    return visible;
  }

  void _next() {
    if (_isLast) {
      widget.onClose();
      return;
    }
    setState(() => _index++);
    _showStep();
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _showStep();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final step = _step;

    final hole = _target?.inflate(step.padding);
    final scrimHole = hole ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);

    return BackButtonListener(
      onBackButtonPressed: () async {
        widget.onClose();
        return true;
      },
      child: Material(
        type: MaterialType.transparency,
        child: FadeTransition(
          opacity: _fade,
          child: Stack(
            children: [
              // Dark scrim with an animated rounded "spotlight" cut-out.
              // Swallows taps so nothing underneath is triggered by accident.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: TweenAnimationBuilder<Rect?>(
                    tween: RectTween(end: scrimHole),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    builder: (context, rect, _) => CustomPaint(
                      painter: _ScrimPainter(rect ?? scrimHole, _pulse),
                    ),
                  ),
                ),
              ),
              // Tooltip card, positioned using its real measured size.
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _CardLayoutDelegate(hole: hole, safe: media.padding),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _measuring
                        ? const SizedBox.shrink(key: ValueKey('measuring'))
                        : _TourCard(
                            key: ValueKey('step_$_index'),
                            step: step,
                            index: _index,
                            total: widget.steps.length,
                            isLast: _isLast,
                            onNext: _next,
                            onBack: _index == 0 ? null : _back,
                            onSkip: widget.onClose,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places the card below the highlighted area when there is room, otherwise
/// above it. With no highlight (welcome step) the card is centered.
class _CardLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect? hole;
  final EdgeInsets safe;
  static const double _side = 16;
  static const double _gap = 14;

  _CardLayoutDelegate({required this.hole, required this.safe});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = math.max(0.0, constraints.maxWidth - _side * 2);
    final maxH = math.max(0.0, constraints.maxHeight - safe.top - safe.bottom - 24);
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: maxH);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minTop = safe.top + 12;
    final maxTop = math.max(minTop, size.height - safe.bottom - 12 - childSize.height);
    double top;
    final h = hole;
    if (h == null) {
      top = (size.height - childSize.height) / 2;
    } else {
      final spaceBelow = size.height - h.bottom;
      final spaceAbove = h.top;
      final fitsBelow = spaceBelow >= childSize.height + _gap + safe.bottom;
      final below = fitsBelow || spaceBelow >= spaceAbove;
      top = below ? h.bottom + _gap : h.top - _gap - childSize.height;
    }
    return Offset(_side, top.clamp(minTop, maxTop).toDouble());
  }

  @override
  bool shouldRelayout(_CardLayoutDelegate old) => old.hole != hole || old.safe != safe;
}

class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final Animation<double> pulse;
  _ScrimPainter(this.hole, this.pulse) : super(repaint: pulse);

  static const double _radius = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final hasHole = hole.width > 1 && hole.height > 1;
    final path = Path()..addRect(Offset.zero & size);
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(_radius));
    if (hasHole) {
      path.addRRect(rrect);
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.78));

    if (hasHole) {
      // Solid ring
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.95),
      );
      // Pulsing ring to draw the eye
      final t = Curves.easeOut.transform(pulse.value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole.inflate(2 + 10 * t), Radius.circular(_radius + 10 * t)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.55 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

class _TourCard extends StatelessWidget {
  final AppTourStep step;
  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  const _TourCard({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                  child: Icon(step.icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h3.copyWith(color: AppColors.primaryDark),
                  ),
                ),
                if (!isLast)
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Skip', style: TextStyle(color: AppColors.textSecondary)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                step.description,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Slim progress bar + counter
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (index + 1) / total,
                            minHeight: 5,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${index + 1}/$total',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (onBack != null)
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                    child: const Text('Back'),
                  ),
                ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    // IMPORTANT: app theme sets minimumSize to Size.fromHeight(52)
                    // (infinite width) which crashes inside a Row. Override it.
                    minimumSize: const Size(88, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(isLast ? 'Got it' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}