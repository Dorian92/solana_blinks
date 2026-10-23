// Swap path: this file is the only one that imports solana_mobile_client.
//
// solana_mobile_client talks to the Mobile Wallet Adapter over a Pigeon
// channel that ships inside that package. To move onto Solana Mobile's
// official Kotlin clientlib, add a KotlinChannelWalletAdapter that implements
// BlinkWalletAdapter and speaks to a new Pigeon or MethodChannel definition
// generated from that clientlib. Pass the new adapter into BlinkCard.
// Widgets, ActionClient, and TransactionExecutor stay as they are.

/// Android Mobile Wallet Adapter implementation of [BlinkWalletAdapter].
///
/// On any platform other than Android, every method that talks to a wallet
/// throws [WalletUnsupportedPlatformException]. iOS support would come from
/// the Kotlin clientlib swap described above, not from this file.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:solana_kit_codecs_strings/solana_kit_codecs_strings.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'blink_wallet_adapter.dart';

/// Connects to an installed Android wallet through Mobile Wallet Adapter.
class MwaWalletAdapter implements BlinkWalletAdapter {
  /// Creates an adapter for [identityName].
  ///
  /// [identityUri] and [iconUri] are shown on the wallet's approval sheet.
  /// [cluster] is a Mobile Wallet Adapter cluster name such as `devnet`,
  /// `testnet`, or `mainnet-beta`.
  MwaWalletAdapter({
    required this.identityUri,
    required this.iconUri,
    required this.identityName,
    this.cluster = 'mainnet-beta',
  });

  /// URI of the app requesting authorization.
  final Uri identityUri;

  /// URI of the icon shown on the approval sheet.
  final Uri iconUri;

  /// Name shown on the approval sheet.
  final String identityName;

  /// Cluster name passed to `authorize`.
  final String cluster;

  String? _authToken;
  String? _publicKey;

  @override
  bool get supportsSignAndSend => true;

  @override
  String? get publicKey => _publicKey;

  @override
  Future<String?> connect() async {
    _requireAndroid();
    if (!await LocalAssociationScenario.isAvailable()) {
      throw const WalletNotInstalledException();
    }
    return _withClient((client) async {
      final existing = _authToken;
      AuthorizationResult? result;
      if (existing != null) {
        result = await client.reauthorize(
          identityUri: identityUri,
          iconUri: iconUri,
          identityName: identityName,
          authToken: existing,
        );
      }
      result ??= await client.authorize(
        identityUri: identityUri,
        iconUri: iconUri,
        identityName: identityName,
        cluster: cluster,
      );
      if (result == null) {
        throw const WalletUserRejectedException();
      }
      _remember(result);
      return _publicKey;
    });
  }

  @override
  Future<void> disconnect() async {
    final token = _authToken;
    _authToken = null;
    _publicKey = null;
    if (token == null || !Platform.isAndroid) {
      return;
    }
    try {
      await _withClient((client) async {
        await client.deauthorize(authToken: token);
      });
    } on WalletException {
      // Local authorization is already cleared.
    }
  }

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> transactions) {
    return _withAuthorizedClient((client) async {
      final signed = await client.signTransactions(transactions: transactions);
      if (signed.signedPayloads.length != transactions.length) {
        throw const WalletUserRejectedException();
      }
      return signed.signedPayloads;
    });
  }

  @override
  Future<List<String>> signAndSendTransactions(List<Uint8List> transactions) {
    return _withAuthorizedClient((client) async {
      final sent = await client.signAndSendTransactions(
        transactions: transactions,
      );
      if (sent.signatures.length != transactions.length) {
        throw const WalletUserRejectedException();
      }
      return <String>[
        for (final signature in sent.signatures)
          getBase58Decoder().decode(signature),
      ];
    });
  }

  Future<T> _withAuthorizedClient<T>(
    Future<T> Function(MobileWalletAdapterClient client) action,
  ) {
    _requireAndroid();
    final token = _authToken;
    if (token == null || _publicKey == null) {
      throw const WalletNotConnectedException();
    }
    return _withClient((client) async {
      final result = await client.reauthorize(
        identityUri: identityUri,
        iconUri: iconUri,
        identityName: identityName,
        authToken: token,
      );
      if (result == null) {
        throw const WalletUserRejectedException();
      }
      _remember(result);
      return action(client);
    });
  }

  void _requireAndroid() {
    if (!Platform.isAndroid) {
      throw const WalletUnsupportedPlatformException(
        'Mobile Wallet Adapter is only available on Android.',
      );
    }
  }

  Future<T> _withClient<T>(
    Future<T> Function(MobileWalletAdapterClient client) action,
  ) async {
    _requireAndroid();
    final session = await LocalAssociationScenario.create();
    try {
      await session.startActivityForResult(null);
      final client = await session.start();
      return await action(client);
    } on WalletException {
      rethrow;
    } on Object catch (error) {
      throw WalletUnknownException('$error');
    } finally {
      await session.close();
    }
  }

  void _remember(AuthorizationResult result) {
    _authToken = result.authToken;
    _publicKey = getBase58Decoder().decode(result.publicKey);
  }
}
