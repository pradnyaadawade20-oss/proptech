import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/role_selection_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/properties/property_detail_screen.dart';
import '../../features/search/map_search_screen.dart';
import '../../features/properties/owner_detail_screen.dart';
import '../../features/properties/property.dart';
import 'route_names.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/owner/owner_dashboard_screen.dart';
import '../../features/broker/broker_dashboard_screen.dart';
import '../../features/visits/visits_screen.dart';
import '../../features/properties/my_properties_screen.dart';
import '../../features/properties/add_property_screen.dart';
import '../../features/chat/chat_list_screen.dart';
import '../../features/chat/chat_detail_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/profile/help_support_screen.dart';
import '../../features/profile/about_screen.dart';
import '../../features/profile/legal_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/search/category_screen.dart';
import '../../features/search/all_categories_screen.dart';
import '../../features/favorites/favorites_screen.dart';
import '../../features/agreement/agreement_request_screen.dart';
import '../../features/agreement/draft_preview_screen.dart';
import '../../features/agreement/agreement_status_screen.dart';
import 'main_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: RouteNames.splash,
  routes: [
    GoRoute(
      path: RouteNames.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: RouteNames.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: RouteNames.otpVerification,
      builder: (context, state) {
        final extra = state.extra as Map<String, String>;
        return OtpScreen(phoneNumber: extra['phone']!, name: extra['name']!);
      },
    ),
    GoRoute(
      path: RouteNames.roleSelection,
      builder: (context, state) => const RoleSelectionScreen(),
    ),

    // Bottom nav tabs
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          child: navigationShell,
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.search,
              builder: (context, state) => SearchScreen(initialQuery: state.extra as String?),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.favorites,
              builder: (context, state) => const FavoritesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.chatList,
              builder: (context, state) => const ChatListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

    // Category screens (Buy / Rent / Commercial / Plot / PG)
    GoRoute(
      path: '/category/:type',
      builder: (context, state) {
        final type = state.pathParameters['type']!;
        final titles = {
          'buy': 'Buy Properties',
          'rent': 'Rent Properties',
          'commercial': 'Commercial',
          'plot': 'Plot / Land',
          'pg': 'PG',
          'furnished': 'Furnished Homes',
          'semifurnished': 'Semifurnished Homes',
          'unfurnished': 'Unfurnished Homes',
          'family': 'For Family',
          'singles': 'For Singles',
          'petfriendly': 'Pet Friendly Homes',
          '1bhk': '1 BHK Properties',
          '2bhk': '2 BHK Properties',
          'rooms': 'Rooms',
          'villa': 'Villa',
          'owner': 'Posted by Owner',
          'dealer': 'Posted by Dealer',
        };
        return CategoryScreen(title: titles[type] ?? 'Properties', filterType: type);
      },
    ),

    // All Categories screen (sidebar + panel, opened from "View all")
    GoRoute(
      path: '/all-categories',
      builder: (context, state) => const AllCategoriesScreen(),
    ),
    GoRoute(
      path: '/map-search',
      builder: (context, state) => const MapSearchScreen(),
    ),

    // Routes outside the bottom nav (pushed on top)
    GoRoute(
      path: '/property/:id',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: PropertyDetailScreen(
          propertyId: state.pathParameters['id']!,
        ),
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
          return FadeTransition(opacity: fade, child: child);
        },
      ),
    ),
    GoRoute(
      path: RouteNames.myVisits,
      builder: (context, state) => const VisitsScreen(),
    ),
    GoRoute(
      path: '/property/:id/owner',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final property = dummyProperties.firstWhere(
          (p) => p.id == id,
          orElse: () => dummyProperties.first,
        );
        return OwnerDetailScreen(property: property);
      },
    ),
    GoRoute(
      path: RouteNames.chatDetail,
      builder: (context, state) => ChatDetailScreen(
        chatId: state.pathParameters['id']!,
        propertyId: state.uri.queryParameters['propertyId'],
      ),
    ),
    GoRoute(
      path: RouteNames.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: RouteNames.helpSupport,
      builder: (context, state) => const HelpSupportScreen(),
    ),
    GoRoute(
      path: RouteNames.about,
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: RouteNames.privacy,
      builder: (context, state) => LegalScreen.privacy(),
    ),
    GoRoute(
      path: RouteNames.terms,
      builder: (context, state) => LegalScreen.terms(),
    ),
    GoRoute(
      path: RouteNames.ownerDashboard,
      builder: (context, state) => const OwnerDashboardScreen(),
    ),
    GoRoute(
      path: RouteNames.brokerDashboard,
      builder: (context, state) => const BrokerDashboardScreen(),
    ),
    GoRoute(
      path: RouteNames.addProperty,
      builder: (context, state) => const AddPropertyScreen(),
    ),
    GoRoute(
      path: RouteNames.myProperties,
      builder: (context, state) => const MyPropertiesScreen(),
    ),
    GoRoute(
      // extra must be a Map with: propertyTitle, propertyImageUrl,
      // counterpartyName, ownerId, tenantId. Pushed from a property's
      // "Request Agreement" action — see AgreementRequestScreen for the
      // shape expected.
      path: RouteNames.agreementRequest,
      builder: (context, state) {
        final propertyId = state.pathParameters['id']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AgreementRequestScreen(
          propertyId: propertyId,
          propertyTitle: extra['propertyTitle'] as String? ?? '',
          propertyImageUrl: extra['propertyImageUrl'] as String? ?? '',
          counterpartyName: extra['counterpartyName'] as String? ?? '',
          ownerId: extra['ownerId'] as String? ?? '',
          tenantId: extra['tenantId'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: RouteNames.agreementDraft,
      builder: (context, state) => DraftPreviewScreen(agreementId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: RouteNames.agreementStatus,
      builder: (context, state) => AgreementStatusScreen(agreementId: state.pathParameters['id']!),
    ),
  ],
);