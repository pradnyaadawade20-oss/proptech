// Basic smoke test: verifies the app boots without throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:proptech_app/app/app.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ProptechApp()),
    );
    await tester.pump();
    expect(find.byType(ProptechApp), findsOneWidget);
  });
}