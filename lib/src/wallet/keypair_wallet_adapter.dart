/// Devnet keypair wallet. Not for production and not for mainnet funds.
///
/// The private key stays in this process. [KeypairWalletAdapter] exists so the
/// example app and local tests can sign action transactions without Mobile
/// Wallet Adapter. A production app should ship an adapter that delegates to
/// a real wallet.
///
/// Signing walks the signatures-first wire format used by legacy and v0
/// transactions: the compact signature array, then the message. The message
/// bytes are signed with [signBytes] and written into the slot whose account
/// key matches this keypair. The message itself is not rewritten.
library;

import 'dart:typed_data';

import 'package:solana_kit_addresses/solana_kit_addresses.dart';
import 'package:solana_kit_keys/solana_kit_keys.dart';

import 'blink_wallet_adapter.dart';

/// In-process Ed25519 signer for development clusters.
///
/// [supportsSignAndSend] is false. The executor submits the signed bytes.
/// [signAndSendTransactions] throws [WalletUnknownException].
class KeypairWalletAdapter implements BlinkWalletAdapter {
  /// Creates an adapter.
  ///
  /// When [keyPair] is omitted, a new random Ed25519 keypair is generated.
  /// `solana_kit` does not expose an HD mnemonic helper, so this is not an
  /// HD wallet.
  KeypairWalletAdapter({KeyPair? keyPair})
    : _keyPair = keyPair ?? generateKeyPair();

  /// Creates an adapter from a 32-byte Ed25519 seed.
  factory KeypairWalletAdapter.fromPrivateKeyBytes(Uint8List privateKey) {
    return KeypairWalletAdapter(
      keyPair: createKeyPairFromPrivateKeyBytes(privateKey),
    );
  }

  final KeyPair _keyPair;
  bool _connected = false;

  /// Base58 address of this keypair, whether or not [connect] has been called.
  String get address => getAddressFromPublicKey(_keyPair.publicKey).value;

  @override
  bool get supportsSignAndSend => false;

  @override
  String? get publicKey => _connected ? address : null;

  @override
  Future<String?> connect() async {
    _connected = true;
    return address;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> transactions) async {
    if (!_connected) {
      throw const WalletNotConnectedException();
    }
    final privateKey = _keyPair.privateKey;
    final publicKey = _keyPair.publicKey;
    try {
      return <Uint8List>[
        for (final transaction in transactions)
          _signWireTransaction(transaction, publicKey, privateKey),
      ];
    } finally {
      privateKey.fillRange(0, privateKey.length, 0);
      publicKey.fillRange(0, publicKey.length, 0);
    }
  }

  @override
  Future<List<String>> signAndSendTransactions(
    List<Uint8List> transactions,
  ) async {
    throw const WalletUnknownException(
      'KeypairWalletAdapter cannot submit transactions. '
      'Sign them and send the bytes with an RPC client.',
    );
  }
}

Uint8List _signWireTransaction(
  Uint8List transaction,
  Uint8List publicKey,
  Uint8List privateKey,
) {
  if (transaction.isEmpty) {
    throw const WalletUnknownException('The transaction is empty.');
  }
  final bytes = Uint8List.fromList(transaction);
  final signatureCount = _readCompactU16(bytes, 0);
  final messageOffset = signatureCount.end + signatureCount.value * 64;
  if (signatureCount.value <= 0 || messageOffset >= bytes.length) {
    throw const WalletUnknownException(
      'The transaction signature section is malformed.',
    );
  }

  final message = Uint8List.sublistView(bytes, messageOffset);
  final headerOffset = message[0] & 0x80 != 0 ? 1 : 0;
  if (message.length < headerOffset + 3) {
    throw const WalletUnknownException(
      'The transaction message header is truncated.',
    );
  }
  final requiredSignatures = message[headerOffset];
  final accounts = _readCompactU16(message, headerOffset + 3);
  final keysOffset = accounts.end;
  if (keysOffset + accounts.value * 32 > message.length) {
    throw const WalletUnknownException(
      'The transaction account keys are truncated.',
    );
  }

  final signerIndex = _signerIndex(
    message,
    keysOffset,
    accounts.value,
    requiredSignatures,
    publicKey,
  );
  if (signerIndex < 0 || signerIndex >= signatureCount.value) {
    throw const WalletUnknownException(
      'This key is not a required signer on the transaction.',
    );
  }

  final signature = signBytes(privateKey, Uint8List.fromList(message));
  final slot = signatureCount.end + signerIndex * 64;
  bytes.setRange(slot, slot + 64, signature.value);
  return bytes;
}

int _signerIndex(
  Uint8List message,
  int keysOffset,
  int accountCount,
  int requiredSignatures,
  Uint8List publicKey,
) {
  final limit = requiredSignatures < accountCount
      ? requiredSignatures
      : accountCount;
  for (var index = 0; index < limit; index++) {
    final start = keysOffset + index * 32;
    if (_sameBytes(message, start, publicKey)) {
      return index;
    }
  }
  return -1;
}

bool _sameBytes(Uint8List message, int start, Uint8List publicKey) {
  if (publicKey.length != 32 || start + 32 > message.length) {
    return false;
  }
  for (var index = 0; index < 32; index++) {
    if (message[start + index] != publicKey[index]) {
      return false;
    }
  }
  return true;
}

({int value, int end}) _readCompactU16(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  var cursor = offset;
  for (var byteCount = 0; byteCount < 3; byteCount++) {
    if (cursor >= bytes.length) {
      throw const WalletUnknownException(
        'The transaction ended inside a compact-u16.',
      );
    }
    final byte = bytes[cursor];
    cursor += 1;
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      return (value: value, end: cursor);
    }
    shift += 7;
  }
  throw const WalletUnknownException(
    'A compact-u16 in the transaction is too long.',
  );
}
