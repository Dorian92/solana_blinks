import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/mwa.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  final wallet = MwaWalletAdapter(
    identityUri: Uri.parse('https://example.com'),
    iconUri: Uri.parse('https://example.com/icon.png'),
    identityName: 'solana_blinks',
    cluster: 'devnet',
  );

  test('reports that sign-and-send is supported', () {
    expect(wallet.supportsSignAndSend, isTrue);
    expect(wallet.publicKey, isNull);
  });

  test('refuses wallet calls when the host is not Android', () async {
    expect(Platform.isAndroid, isFalse, reason: 'flutter test runs on a VM');

    expect(wallet.connect, throwsA(isA<WalletUnsupportedPlatformException>()));
    expect(
      () => wallet.signTransactions(<Uint8List>[Uint8List(1)]),
      throwsA(isA<WalletUnsupportedPlatformException>()),
    );
    expect(
      () => wallet.signAndSendTransactions(<Uint8List>[Uint8List(1)]),
      throwsA(isA<WalletUnsupportedPlatformException>()),
    );

    await wallet.disconnect();
    expect(wallet.publicKey, isNull);
  });
}
