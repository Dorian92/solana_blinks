import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solana_kit_keys/solana_kit_keys.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  group('KeypairWalletAdapter', () {
    test('signs the message slot that matches its public key', () async {
      final keyPair = generateKeyPair();
      final other = generateKeyPair();
      final wallet = KeypairWalletAdapter(keyPair: keyPair);
      final unsigned = _unsignedTransaction(
        signers: <Uint8List>[other.publicKey, keyPair.publicKey],
        versioned: false,
      );

      expect(wallet.publicKey, isNull);
      expect(wallet.supportsSignAndSend, isFalse);
      expect(await wallet.connect(), wallet.address);

      final signed = (await wallet.signTransactions(<Uint8List>[unsigned]))
          .single;
      final message = signed.sublist(1 + 128);
      final ourSignature = signed.sublist(1 + 64, 1 + 128);

      expect(signed.sublist(1, 1 + 64), everyElement(0));
      expect(message, unsigned.sublist(1 + 128));
      expect(
        verifySignature(
          keyPair.publicKey,
          SignatureBytes(Uint8List.fromList(ourSignature)),
          Uint8List.fromList(message),
        ),
        isTrue,
      );
    });

    test('signs a versioned v0 message without rewriting it', () async {
      final keyPair = generateKeyPair();
      final wallet = KeypairWalletAdapter(keyPair: keyPair);
      await wallet.connect();
      final unsigned = _unsignedTransaction(
        signers: <Uint8List>[keyPair.publicKey],
        versioned: true,
      );

      final signed = (await wallet.signTransactions(<Uint8List>[unsigned]))
          .single;
      final message = signed.sublist(65);

      expect(message, unsigned.sublist(65));
      expect(message.first, 0x80);
      expect(
        verifySignature(
          keyPair.publicKey,
          SignatureBytes(Uint8List.fromList(signed.sublist(1, 65))),
          Uint8List.fromList(message),
        ),
        isTrue,
      );
    });

    test('refuses a transaction this key does not sign', () async {
      final wallet = KeypairWalletAdapter();
      await wallet.connect();
      final unsigned = _unsignedTransaction(
        signers: <Uint8List>[generateKeyPair().publicKey],
        versioned: false,
      );

      expect(
        () => wallet.signTransactions(<Uint8List>[unsigned]),
        throwsA(isA<WalletUnknownException>()),
      );
    });

    test('requires connect and does not submit', () async {
      final wallet = KeypairWalletAdapter();

      expect(
        () => wallet.signTransactions(<Uint8List>[Uint8List(0)]),
        throwsA(isA<WalletNotConnectedException>()),
      );
      expect(
        () => wallet.signAndSendTransactions(<Uint8List>[Uint8List(0)]),
        throwsA(isA<WalletUnknownException>()),
      );
    });

    test('restores a key from a 32-byte seed', () {
      final seed = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      final fromSeed = KeypairWalletAdapter.fromPrivateKeyBytes(seed);
      final fromPair = KeypairWalletAdapter(
        keyPair: createKeyPairFromPrivateKeyBytes(seed),
      );

      expect(fromSeed.address, fromPair.address);
    });
  });
}

Uint8List _unsignedTransaction({
  required List<Uint8List> signers,
  required bool versioned,
}) {
  final message = BytesBuilder(copy: false)
    ..add(
      versioned
          ? <int>[0x80, signers.length, 0, 0]
          : <int>[signers.length, 0, 0],
    )
    ..addByte(signers.length);
  for (final signer in signers) {
    message.add(signer);
  }
  message
    ..add(Uint8List(32))
    ..addByte(0);
  if (versioned) {
    message.addByte(0);
  }

  final transaction = BytesBuilder(copy: false)..addByte(signers.length);
  for (var index = 0; index < signers.length; index++) {
    transaction.add(Uint8List(64));
  }
  transaction.add(message.toBytes());
  return transaction.toBytes();
}
