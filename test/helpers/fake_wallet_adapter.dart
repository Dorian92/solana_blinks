/// In-memory [BlinkWalletAdapter] for tests.
library;

import 'dart:typed_data';

import 'package:solana_blinks/solana_blinks.dart';

/// Wallet double that records signing calls and returns canned results.
class FakeWalletAdapter implements BlinkWalletAdapter {
  /// Creates a fake wallet.
  ///
  /// [failure] is thrown from the next wallet call when it is set.
  /// [signAndSendSignatures] is returned by [signAndSendTransactions], one
  /// entry per transaction when the lengths differ the list is repeated or
  /// truncated to the transaction count.
  FakeWalletAdapter({
    this.address = 'FakePubkey1111111111111111111111111111111',
    this.supportsSignAndSend = false,
    this.signAndSendSignatures = const <String>['fakeSignature'],
    this.failure,
  });

  /// Public key returned by [connect].
  final String address;

  /// Signatures returned by [signAndSendTransactions].
  final List<String> signAndSendSignatures;

  /// Failure thrown by the next method, when set.
  WalletException? failure;

  final List<List<Uint8List>> _signed = <List<Uint8List>>[];
  String? _publicKey;
  bool _connected = false;

  /// Transactions passed to [signTransactions], in call order.
  List<List<Uint8List>> get signedTransactions =>
      List<List<Uint8List>>.unmodifiable(_signed);

  /// Whether [connect] has succeeded and [disconnect] has not run.
  bool get isConnected => _connected;

  @override
  bool supportsSignAndSend;

  @override
  String? get publicKey => _publicKey;

  @override
  Future<String?> connect() async {
    _throwIfNeeded();
    _connected = true;
    _publicKey = address;
    return address;
  }

  @override
  Future<void> disconnect() async {
    _throwIfNeeded();
    _connected = false;
    _publicKey = null;
  }

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> transactions) async {
    _throwIfNeeded();
    _requireConnection();
    _signed.add(transactions.map(Uint8List.fromList).toList());
    return transactions.map(Uint8List.fromList).toList();
  }

  @override
  Future<List<String>> signAndSendTransactions(
    List<Uint8List> transactions,
  ) async {
    _throwIfNeeded();
    _requireConnection();
    if (!supportsSignAndSend) {
      throw const WalletUnknownException('This wallet cannot sign and send.');
    }
    _signed.add(transactions.map(Uint8List.fromList).toList());
    if (signAndSendSignatures.isEmpty) {
      return List<String>.filled(transactions.length, 'fakeSignature');
    }
    return <String>[
      for (var index = 0; index < transactions.length; index++)
        signAndSendSignatures[index % signAndSendSignatures.length],
    ];
  }

  void _requireConnection() {
    if (!_connected || _publicKey == null) {
      throw const WalletNotConnectedException();
    }
  }

  void _throwIfNeeded() {
    final pending = failure;
    if (pending != null) {
      throw pending;
    }
  }
}
