import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../notifications/push_notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
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
    } catch (e) {
      debugPrint('Splash openRoute failed: $e');
    }
    if (!mounted) return;
    context.go(RouteNames.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Text(
          'PropTech',
          style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 32),
        ),
      ),
    );
  }
}