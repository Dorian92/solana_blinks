import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:solana_kit_rpc/solana_kit_rpc.dart';
import 'package:solana_blinks_example_server/tip_action.dart';

/// Devnet RPC used to fetch a recent blockhash for the unsigned tip.
const String devnetRpcUrl = 'https://api.devnet.solana.com';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? devnetRpcUrl;
  final handler = Pipeline().addHandler(
    (request) => handleTip(request, rpcUrl),
  );
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Tip action listening on http://${server.address.host}:${server.port}/tip',
  );
  stdout.writeln('Treasury: $tipDestination');
}

/// Routes Action requests for the local tip.
Future<Response> handleTip(Request request, String rpcUrl) async {
  if (request.method == 'OPTIONS') {
    return Response(204, headers: actionCorsHeaders);
  }

  final path = request.url.path;
  if (request.method == 'GET' && path == 'actions.json') {
    return _json(tipActionsJson());
  }
  if (request.method == 'GET' && (path == 'tip' || path == 'api/tip')) {
    return _json(tipActionResponse());
  }
  if (request.method == 'POST' && path == 'api/tip') {
    return _postTip(request, rpcUrl);
  }
  return _json(<String, Object?>{'message': 'Not found.'}, status: 404);
}

Future<Response> _postTip(Request request, String rpcUrl) async {
  final amount = lamportsFromSol(request.url.queryParameters['amount'] ?? '');
  if (amount == null ||
      amount < BigInt.from(1000000) ||
      amount > BigInt.from(1000000000)) {
    return _json(<String, Object?>{
      'message': 'Amount must be between 0.001 and 1 SOL.',
    }, status: 400);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException {
    return _json(<String, Object?>{
      'message': 'The request body was not valid JSON.',
    }, status: 400);
  }
  if (decoded is! Map || decoded['account'] is! String) {
    return _json(<String, Object?>{
      'message': 'The request must include an account.',
    }, status: 400);
  }
  final account = decoded['account'] as String;

  try {
    final rpc = createSolanaRpc(url: rpcUrl);
    final latest = await rpc.getLatestBlockhashValue().send().timeout(
      const Duration(seconds: 20),
    );
    final transaction = buildUnsignedTipTransaction(
      account: account,
      destination: tipDestination,
      lamports: amount,
      blockhash: latest.value.blockhash.value,
      lastValidBlockHeight: latest.value.lastValidBlockHeight,
    );
    return _json(<String, Object?>{
      'transaction': transaction,
      'message':
          'Sign this devnet tip of ${request.url.queryParameters['amount']} SOL.',
    });
  } on Object catch (error) {
    return _json(<String, Object?>{
      'message': 'Could not build the tip transaction: $error',
    }, status: 502);
  }
}

Response _json(Object? body, {int status = 200}) {
  return Response(status, body: jsonEncode(body), headers: actionCorsHeaders);
}
