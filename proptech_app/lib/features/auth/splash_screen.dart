import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../../core/session/user_session.dart';
import '../notifications/push_notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _next);
  }

  Future<void> _next() async {
    // App was killed and the user tapped a push -> open that screen directly.
    String? route;
    try {
      if (await TokenStore.instance.isLoggedIn()) {
        await UserSession.instance.restore();
        route = await PushNotificationService.instance.launchRoute
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
      }
    } catch (e) {
      // Whatever goes wrong here (secure storage, push), never get stuck on
      // the splash screen — just fall through to onboarding.
      debugPrint('Splash startup check failed: $e');
    }
    if (!mounted) return;
    try {
      if (route != null) {
        await PushNotificationService.instance.openRoute(route);
        return;
      }
      // Already logged in on this device -> skip onboarding/login.
      if (await TokenStore.instance.isLoggedIn()) {
        context.go(RouteNames.home);
        return;
      }
    } catch (e) {
      debugPrint('Splash openRoute failed: $e');
    }
    if (!mounted) return;
    context.go(RouteNames.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(fade),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', width: 190, height: 190),
                const SizedBox(height: 4),
                Text(
                  'PropTech',
                  style: AppTextStyles.h1.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find your perfect space',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}