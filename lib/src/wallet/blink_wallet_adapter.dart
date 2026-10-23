/// The only wallet boundary in this package.
///
/// Widgets and the transaction executor call [BlinkWalletAdapter]. They never
/// import a wallet SDK. Swap in Mobile Wallet Adapter, a devnet keypair, or a
/// custom signer by implementing this type.
library;

import 'dart:typed_data';

/// Failure raised by a [BlinkWalletAdapter] implementation.
sealed class WalletException implements Exception {
  /// Creates a wallet failure with a message safe to show the user.
  const WalletException(this.message);

  /// Message to display.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The user dismissed or rejected the wallet request.
class WalletUserRejectedException extends WalletException {
  /// Creates a user-rejected failure.
  const WalletUserRejectedException([
    super.message = 'The wallet request was rejected.',
  ]);
}

/// A signing method was called before [BlinkWalletAdapter.connect].
class WalletNotConnectedException extends WalletException {
  /// Creates a not-connected failure.
  const WalletNotConnectedException([
    super.message = 'Connect a wallet before signing.',
  ]);
}

/// This device has no wallet that can handle the request.
class WalletNotInstalledException extends WalletException {
  /// Creates a no-wallet failure.
  const WalletNotInstalledException([
    super.message = 'No compatible wallet is installed.',
  ]);
}

/// The adapter does not run on this platform.
class WalletUnsupportedPlatformException extends WalletException {
  /// Creates an unsupported-platform failure.
  const WalletUnsupportedPlatformException([
    super.message = 'This wallet adapter is not supported on this platform.',
  ]);
}

/// A wallet failure that does not match a more specific type.
class WalletUnknownException extends WalletException {
  /// Creates an unknown wallet failure.
  const WalletUnknownException([super.message = 'The wallet request failed.']);
}

/// Signs Solana transactions for a blink.
///
/// This is the only boundary between the package and a wallet. Implementations
/// can be swapped without changing [BlinkCard] or the action client. The
/// adapter receives transaction bytes built by the Action server and returns
/// signatures or signed bytes. It does not construct transactions.
abstract class BlinkWalletAdapter {
  /// Connects to the wallet.
  ///
  /// Returns the base58 public key of the selected account. Returns `null`
  /// when the user dismisses the request without it being an error the caller
  /// should treat as a failure. Throws a [WalletException] when the wallet
  /// cannot be reached.
  Future<String?> connect();

  /// Base58 public key of the connected account, or `null` when disconnected.
  String? get publicKey;

  /// Forgets the connected account.
  ///
  /// Implementations should also tell the wallet to drop its authorization
  /// when the underlying protocol supports that.
  Future<void> disconnect();

  /// Signs each transaction and returns the signed wire bytes, in order.
  ///
  /// Does not submit anything to the cluster. Throws [WalletNotConnectedException]
  /// when [publicKey] is `null`, and [WalletUserRejectedException] when the
  /// user rejects the sheet.
  Future<List<Uint8List>> signTransactions(List<Uint8List> transactions);

  /// Signs and submits each transaction.
  ///
  /// Returns base58 transaction signatures, in order. Only call this when
  /// [supportsSignAndSend] is true. Throws [WalletNotConnectedException] when
  /// no account is connected, and [WalletUserRejectedException] when the user
  /// rejects the sheet.
  Future<List<String>> signAndSendTransactions(List<Uint8List> transactions);

  /// Whether [signAndSendTransactions] is implemented.
  ///
  /// When this is false, the executor signs with [signTransactions] and
  /// submits the signed bytes itself.
  bool get supportsSignAndSend;
}
