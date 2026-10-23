import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana_kit_codecs_strings/solana_kit_codecs_strings.dart';
import 'package:solana_blinks/solana_blinks.dart';

import '../helpers/fake_wallet_adapter.dart';

void main() {
  const rpcUrl = 'https://rpc.test';
  const signature = 'submittedSignature';

  group('TransactionExecutor', () {
    test('submits signed bytes and polls until confirmed', () async {
      final wallet = FakeWalletAdapter();
      await wallet.connect();
      final seen = <Map<String, Object?>>[];
      var polls = 0;
      final executor = TransactionExecutor(
        wallet: wallet,
        rpcUrl: rpcUrl,
        pollInterval: const Duration(milliseconds: 1),
        httpClient: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          seen.add(payload);
          final method = payload['method'];
          if (method == 'sendTransaction') {
            return _rpc(payload['id'], signature);
          }
          polls += 1;
          final status = polls < 2
              ? <String, Object?>{
                  'confirmationStatus': 'processed',
                  'err': null,
                }
              : <String, Object?>{
                  'confirmationStatus': 'confirmed',
                  'err': null,
                };
          return _rpc(payload['id'], <String, Object?>{
            'context': <String, Object?>{'slot': 1},
            'value': <Object?>[status],
          });
        }),
      );

      final result = await executor.execute(
        const ActionPostResponse(transaction: 'AQIDBA=='),
      );

      expect(result, isA<ExecutionSuccess>());
      expect((result as ExecutionSuccess).signature, signature);
      expect(seen.map((payload) => payload['method']), <Object?>[
        'sendTransaction',
        'getSignatureStatuses',
        'getSignatureStatuses',
      ]);
      final params = seen.first['params']! as List<Object?>;
      expect(
        params.first,
        getBase64Decoder().decode(getBase64Encoder().encode('AQIDBA==')),
      );
      final config = params[1]! as Map<String, Object?>;
      expect(config['encoding'], 'base64');
      expect(wallet.signedTransactions, hasLength(1));
    });

    test('uses the wallet signature when sign-and-send is supported', () async {
      final wallet = FakeWalletAdapter(
        supportsSignAndSend: true,
        signAndSendSignatures: const <String>['walletSignature'],
      );
      await wallet.connect();
      final methods = <String>[];
      final executor = TransactionExecutor(
        wallet: wallet,
        rpcUrl: rpcUrl,
        pollInterval: Duration.zero,
        httpClient: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          methods.add(payload['method']! as String);
          expect(payload['method'], isNot('sendTransaction'));
          return _rpc(payload['id'], <String, Object?>{
            'context': <String, Object?>{'slot': 4},
            'value': <Object?>[
              <String, Object?>{'confirmationStatus': 'finalized', 'err': null},
            ],
          });
        }),
      );

      final result = await executor.execute(
        const ActionPostResponse(transaction: 'AQID'),
      );

      expect((result as ExecutionSuccess).signature, 'walletSignature');
      expect(methods, <String>['getSignatureStatuses']);
    });

    test('returns a failure when the signature status has an error', () async {
      final wallet = FakeWalletAdapter(supportsSignAndSend: true);
      await wallet.connect();
      final executor = TransactionExecutor(
        wallet: wallet,
        rpcUrl: rpcUrl,
        httpClient: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          return _rpc(payload['id'], <String, Object?>{
            'context': <String, Object?>{'slot': 1},
            'value': <Object?>[
              <String, Object?>{
                'err': <String, Object?>{'InstructionError': 'Custom'},
                'confirmationStatus': 'confirmed',
              },
            ],
          });
        }),
      );

      final result = await executor.execute(
        const ActionPostResponse(transaction: 'AQID'),
      );

      expect(result, isA<ExecutionFailure>());
      expect((result as ExecutionFailure).reason, contains('InstructionError'));
    });

    test('returns a failure when confirmation times out', () async {
      final wallet = FakeWalletAdapter(supportsSignAndSend: true);
      await wallet.connect();
      final executor = TransactionExecutor(
        wallet: wallet,
        rpcUrl: rpcUrl,
        confirmationTimeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 5),
        httpClient: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          return _rpc(payload['id'], <String, Object?>{
            'context': <String, Object?>{'slot': 1},
            'value': <Object?>[null],
          });
        }),
      );

      final result = await executor.execute(
        const ActionPostResponse(transaction: 'AQID'),
      );

      expect(result, isA<ExecutionFailure>());
      expect((result as ExecutionFailure).reason, contains('Timed out'));
    });

    test('returns a failure when the wallet rejects the request', () async {
      final wallet = FakeWalletAdapter(
        failure: const WalletUserRejectedException(),
      );
      final executor = TransactionExecutor(
        wallet: wallet,
        rpcUrl: rpcUrl,
        httpClient: MockClient((request) async => http.Response('nope', 500)),
      );

      final result = await executor.execute(
        const ActionPostResponse(transaction: 'AQID'),
      );

      expect(result, isA<ExecutionFailure>());
      expect((result as ExecutionFailure).reason, contains('rejected'));
    });

    test('returns a failure when the response has no transaction', () async {
      final executor = TransactionExecutor(
        wallet: FakeWalletAdapter(),
        rpcUrl: rpcUrl,
      );

      final result = await executor.execute(const ActionPostResponse());

      expect(
        (result as ExecutionFailure).reason,
        contains('did not return a transaction'),
      );
    });
  });
}

http.Response _rpc(Object? id, Object? result) {
  return http.Response(
    jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
