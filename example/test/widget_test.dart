import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_example/main.dart';

void main() {
  testWidgets('shows the public reusable picker', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Select video'), findsOneWidget);
    expect(find.byKey(const ValueKey('lux-video-select')), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('opens and cancels the public thumbnail dialog', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(
      find.byKey(const ValueKey('example-open-thumbnail-dialog')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lux-video-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
