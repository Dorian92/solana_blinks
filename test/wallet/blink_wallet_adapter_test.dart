import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/solana_blinks.dart';

import '../helpers/fake_wallet_adapter.dart';

void main() {
  group('FakeWalletAdapter', () {
    test('connects, signs, and disconnects', () async {
      final wallet = FakeWalletAdapter();
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(await wallet.connect(), wallet.address);
      expect(wallet.publicKey, wallet.address);

      final signed = await wallet.signTransactions(<Uint8List>[bytes]);
      expect(signed.single, bytes);
      expect(wallet.signedTransactions.single.single, bytes);

      await wallet.disconnect();
      expect(wallet.publicKey, isNull);
      expect(
        () => wallet.signTransactions(<Uint8List>[bytes]),
        throwsA(isA<WalletNotConnectedException>()),
      );
    });

    test('sign-and-send returns one signature per transaction', () async {
      final wallet = FakeWalletAdapter(
        supportsSignAndSend: true,
        signAndSendSignatures: const <String>['sigA', 'sigB'],
      );
      await wallet.connect();

      final signatures = await wallet.signAndSendTransactions(<Uint8List>[
        Uint8List(1),
        Uint8List(1),
        Uint8List(1),
      ]);

      expect(signatures, <String>['sigA', 'sigB', 'sigA']);
    });

    test('surfaces the configured wallet failure', () async {
      final wallet = FakeWalletAdapter(
        failure: const WalletNotInstalledException(),
      );

      expect(wallet.connect, throwsA(isA<WalletNotInstalledException>()));
    });
  });

  test('wallet exceptions keep their message', () {
    const rejected = WalletUserRejectedException();
    const unknown = WalletUnknownException('cluster rejected the signature');

    expect(rejected.message, contains('rejected'));
    expect(unknown.toString(), contains('cluster rejected'));
    expect(const WalletUnsupportedPlatformException(), isA<WalletException>());
  });
}
