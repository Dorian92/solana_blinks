/// Submits an action transaction and waits for confirmation.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:solana_kit_codecs_strings/solana_kit_codecs_strings.dart';
import 'package:solana_kit_keys/solana_kit_keys.dart';
import 'package:solana_kit_rpc/solana_kit_rpc.dart';
import 'package:solana_kit_rpc_spec/solana_kit_rpc_spec.dart';
import 'package:solana_kit_rpc_api/solana_kit_rpc_api.dart';
import 'package:solana_kit_rpc_types/solana_kit_rpc_types.dart';

import '../wallet/blink_wallet_adapter.dart';
import 'models.dart';

/// Outcome of submitting an action transaction.
sealed class ExecutionResult {
  /// Creates a result.
  const ExecutionResult();
}

/// The transaction reached `confirmed` or `finalized`.
class ExecutionSuccess extends ExecutionResult {
  /// Creates a successful result.
  const ExecutionSuccess(this.signature);

  /// Base58 signature of the submitted transaction.
  final String signature;
}

/// The wallet, the cluster, or the confirmation wait failed.
class ExecutionFailure extends ExecutionResult {
  /// Creates a failed result.
  const ExecutionFailure(this.reason);

  /// Reason safe to show in the blink card.
  final String reason;
}

/// Signs an [ActionPostResponse] and confirms it on a Solana cluster.
///
/// The Action server builds the transaction. This executor base64-decodes the
/// bytes and hands them to [wallet] unchanged. When [BlinkWalletAdapter.supportsSignAndSend]
/// is false, the signed bytes are submitted with `sendTransaction` using
/// base64 encoding, then `getSignatureStatuses` is polled until the status is
/// confirmed or [confirmationTimeout] elapses.
class TransactionExecutor {
  /// Creates an executor for [rpcUrl].
  ///
  /// [httpClient] replaces the RPC transport's client. Tests use it to mock
  /// `sendTransaction` and `getSignatureStatuses`.
  TransactionExecutor({
    required this.wallet,
    required this.rpcUrl,
    this.httpClient,
    this.confirmationTimeout = const Duration(seconds: 60),
    this.pollInterval = const Duration(seconds: 2),
  });

  /// Wallet that signs, and maybe submits, the transaction.
  final BlinkWalletAdapter wallet;

  /// Cluster RPC HTTP endpoint, for example `https://api.devnet.solana.com`.
  final String rpcUrl;

  /// Optional HTTP client for the RPC transport.
  final http.Client? httpClient;

  /// How long to poll for confirmation.
  final Duration confirmationTimeout;

  /// Delay between `getSignatureStatuses` calls.
  final Duration pollInterval;

  /// Signs [response.transaction] and waits until it is confirmed.
  Future<ExecutionResult> execute(ActionPostResponse response) async {
    final encoded = response.transaction?.trim();
    if (encoded == null || encoded.isEmpty) {
      return const ExecutionFailure('The action did not return a transaction.');
    }

    final Uint8List transaction;
    try {
      transaction = getBase64Encoder().encode(encoded);
    } on Object {
      return const ExecutionFailure(
        'The action transaction was not valid base64.',
      );
    }

    try {
      final signature = wallet.supportsSignAndSend
          ? await _signAndSend(transaction)
          : await _signAndSubmit(transaction);
      return await _confirm(signature);
    } on WalletException catch (error) {
      return ExecutionFailure(error.message);
    } on Object catch (error) {
      return ExecutionFailure('$error');
    }
  }

  Future<String> _signAndSend(Uint8List transaction) async {
    final signatures = await wallet.signAndSendTransactions(<Uint8List>[
      transaction,
    ]);
    if (signatures.isEmpty || signatures.first.isEmpty) {
      throw const WalletUnknownException(
        'The wallet did not return a signature.',
      );
    }
    return signatures.first;
  }

  Future<String> _signAndSubmit(Uint8List transaction) async {
    final signed = await wallet.signTransactions(<Uint8List>[transaction]);
    if (signed.isEmpty) {
      throw const WalletUnknownException(
        'The wallet did not return a signed transaction.',
      );
    }
    final rpc = _rpc();
    return rpc
        .sendTransaction(
          getBase64Decoder().decode(signed.first),
          const SendTransactionConfig(
            encoding: WireTransactionEncoding.base64,
            preflightCommitment: Commitment.confirmed,
          ),
        )
        .send();
  }

  Future<ExecutionResult> _confirm(String signature) async {
    final rpc = _rpc();
    final deadline = DateTime.now().add(confirmationTimeout);
    while (true) {
      final result = await rpc.getSignatureStatuses(<Signature>[
        Signature(signature),
      ]).send();
      final outcome = _interpretStatus(signature, result);
      if (outcome != null) {
        return outcome;
      }
      if (!DateTime.now().isBefore(deadline)) {
        return ExecutionFailure('Timed out waiting for $signature to confirm.');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  ExecutionResult? _interpretStatus(
    String signature,
    Map<String, Object?> result,
  ) {
    final value = result['value'];
    if (value is! List || value.isEmpty || value.first == null) {
      return null;
    }
    final status = value.first;
    if (status is! Map) {
      return null;
    }
    final error = status['err'];
    if (error != null) {
      return ExecutionFailure('Transaction $signature failed: $error');
    }
    final confirmation = status['confirmationStatus'];
    if (confirmation == 'confirmed' || confirmation == 'finalized') {
      return ExecutionSuccess(signature);
    }
    return null;
  }

  Rpc _rpc() {
    return createSolanaRpc(
      url: rpcUrl,
      client: httpClient,
      allowInsecureHttp: rpcUrl.startsWith('http://'),
    );
  }
}
