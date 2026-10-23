import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/solana_blinks.dart';
import 'package:solana_blinks_example/main.dart';

void main() {
  testWidgets('lists sample blinks and toggles the wallet', (tester) async {
    await tester.pumpWidget(const BlinksExampleApp());

    expect(find.text('Local devnet tip'), findsOneWidget);
    expect(find.text('Local tip via solana-action'), findsOneWidget);
    expect(find.text('Emulator host tip'), findsOneWidget);
    expect(find.text('Keypair (devnet)'), findsOneWidget);
    expect(find.byKey(const Key('devnet-address')), findsOneWidget);
    expect(find.byType(BlinkCard), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Mobile Wallet Adapter'), findsOneWidget);
    expect(find.byKey(const Key('devnet-address')), findsNothing);
  });
}
