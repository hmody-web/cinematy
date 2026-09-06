import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cinematy/app.dart';

void main() {
  testWidgets('Cinematy renders Arabic shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CinematyApp()));
    await tester.pump();
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
