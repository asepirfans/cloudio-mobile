import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudio_mobile/main.dart';

void main() {
  testWidgets('CloudioApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CloudioApp());
    expect(find.text('Cloudio', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel('Logo Cloudio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
