/// Central place for all route path strings.
class RouteNames {
  RouteNames._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const otpVerification = '/otp-verification'; 
  static const roleSelection = '/role-selection';

  static const home = '/home';
  static const search = '/search';
  static const propertyDetail = '/property/:id';
  static const favorites = '/favorites';

  static const scheduleVisit = '/property/:id/visit';
  static const myVisits = '/visits';

  static const chatList = '/chats';
  static const chatDetail = '/chats/:id';
  // Standalone copy of the chat list, used when pushing on top of a
  // non-shell screen (e.g. Owner/Broker Dashboard). Pushing the shell's
  // own `chatList` branch route reuses a GlobalKey that's already mounted
  // in the shell below, which crashes with a duplicate-GlobalKey assertion.
  static const chatListStandalone = '/chats-view';

  static const profile = '/profile';
  // Standalone copy of profile, used when pushing on top of a non-shell
  // screen (Owner/Broker Dashboard) — same GlobalKey conflict as chatListStandalone.
  static const profileStandalone = '/profile-view';
  static const emiCalculator = '/emi-calculator';

  // Owner
  static const ownerDashboard = '/owner';
  static const addProperty = '/owner/add-property';
  static const myProperties = '/owner/properties';

  // Broker
  static const brokerDashboard = '/broker';

  // Agreement
  static const agreementRequest = '/property/:id/agreement/request';
  static const agreementDraft = '/agreement/:id/draft';
  static const agreementSignature = '/agreement/:id/sign';
  static const agreementStatus = '/agreement/:id/status';
}