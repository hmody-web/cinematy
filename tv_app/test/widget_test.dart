import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cinematy/app.dart';

void main() {
  testWidgets('Cinematy app loads', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CinematyApp(),
      ),
    );

    await tester.pump();
  });
}
