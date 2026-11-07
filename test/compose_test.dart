import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:via_app/src/config.dart';
import 'package:via_app/src/sender.dart';
import 'package:via_app/ui/compose.dart';

void main() {
  testWidgets('share popup switches a link to text and back', (tester) async {
    final kinds = <SendKind>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposeForm(
            account: Account(server: 'http://localhost', deviceId: 'd', deviceName: 'n', token: 't'),
            kind: SendKind.link,
            initialText: 'https://example.com',
            popup: true,
            onSent: (_) {},
            onKindChanged: kinds.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Send as text'));
    await tester.pump();
    expect(kinds, [SendKind.text]);
    expect(find.widgetWithText(TextField, 'https://example.com'), findsOneWidget);

    await tester.tap(find.text('Send as link'));
    await tester.pump();
    expect(kinds, [SendKind.text, SendKind.link]);
  });
}
