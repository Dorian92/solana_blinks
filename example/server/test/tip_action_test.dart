import 'dart:convert';
import 'dart:typed_data';

import 'package:solana_kit_addresses/solana_kit_addresses.dart';
import 'package:solana_kit_keys/solana_kit_keys.dart';
import 'package:solana_blinks_example_server/tip_action.dart';
import 'package:test/test.dart';

void main() {
  group('lamportsFromSol', () {
    test('scales decimal SOL without binary rounding', () {
      expect(lamportsFromSol('0.001'), BigInt.from(1000000));
      expect(lamportsFromSol('1'), BigInt.from(1000000000));
      expect(lamportsFromSol('0.000000001'), BigInt.one);
      expect(lamportsFromSol('1.5'), BigInt.from(1500000000));
    });

    test('rejects signs, extra precision, and junk', () {
      expect(lamportsFromSol('-1'), isNull);
      expect(lamportsFromSol('0.0000000001'), isNull);
      expect(lamportsFromSol('nope'), isNull);
      expect(lamportsFromSol(''), isNull);
    });
  });

  test('buildUnsignedTipTransaction leaves the fee payer signature empty', () {
    final payer = generateKeyPair();
    final account = getAddressFromPublicKey(payer.publicKey).value;
    final blockhash = getAddressFromPublicKey(generateKeyPair().publicKey)
        .value;

    final encoded = buildUnsignedTipTransaction(
      account: account,
      destination: tipDestination,
      lamports: BigInt.from(1000000),
      blockhash: blockhash,
      lastValidBlockHeight: BigInt.from(100),
    );

    final bytes = Uint8List.fromList(base64Decode(encoded));
    expect(bytes.first, 1);
    expect(bytes.sublist(1, 65), everyElement(0));
    expect(encoded, isNotEmpty);
    expect(account, isA<String>());
  });
}
