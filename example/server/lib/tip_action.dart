/// Builds the devnet tip Action and its unsigned transfer.
library;

import 'package:solana_kit_addresses/solana_kit_addresses.dart';
import 'package:solana_kit_system/solana_kit_system.dart';
import 'package:solana_kit_transaction_messages/solana_kit_transaction_messages.dart';
import 'package:solana_kit_transactions/solana_kit_transactions.dart';

/// Treasury that receives example tips.
///
/// This address is not funded. The first successful transfer creates it.
const String tipDestination = '2gQtZ7GKv48WCsbU1smKqm3akgzYGHhV1EFTiFKpcWYZ';

/// Headers required by the Solana Actions CORS preflight.
const Map<String, String> actionCorsHeaders = <String, String>{
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,OPTIONS',
  'Access-Control-Allow-Headers':
      'Content-Type, Authorization, Content-Encoding, Accept-Encoding',
  'Content-Type': 'application/json; charset=utf-8',
};

/// `actions.json` rules for the local tip site.
Map<String, Object?> tipActionsJson() {
  return <String, Object?>{
    'rules': <Object?>[
      <String, Object?>{'pathPattern': '/tip', 'apiPath': '/api/tip'},
      <String, Object?>{'pathPattern': '/api/tip', 'apiPath': '/api/tip'},
    ],
  };
}

/// GET body for the devnet SOL tip.
Map<String, Object?> tipActionResponse() {
  return <String, Object?>{
    'type': 'action',
    'icon': '',
    'title': 'Devnet tip',
    'description':
        'Send a small amount of devnet SOL to the example treasury $tipDestination.',
    'label': 'Send tip',
    'links': <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'action',
          'label': 'Send tip',
          'href': '/api/tip?amount={amount}',
          'parameters': <Object?>[
            <String, Object?>{
              'name': 'amount',
              'label': 'Amount in SOL',
              'required': true,
              'type': 'number',
              'min': 0.001,
              'max': 1,
            },
          ],
        },
      ],
    },
  };
}

/// Converts a SOL decimal string into lamports.
///
/// Returns `null` when [raw] is not a non-negative decimal with at most 9
/// fractional digits. Whole SOL and the fractional part are scaled in base 10
/// so `0.001` is exactly `1000000` lamports.
BigInt? lamportsFromSol(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('-') || trimmed.startsWith('+')) {
    return null;
  }
  final pieces = trimmed.split('.');
  if (pieces.length > 2 || pieces.first.isEmpty && pieces.length == 1) {
    return null;
  }
  final whole = pieces.first.isEmpty ? '0' : pieces.first;
  if (!RegExp(r'^\d+$').hasMatch(whole)) {
    return null;
  }
  final fraction = pieces.length == 2 ? pieces[1] : '';
  if (fraction.length > 9 || !RegExp(r'^\d*$').hasMatch(fraction)) {
    return null;
  }
  final digits = '$whole${fraction.padRight(9, '0')}';
  return BigInt.tryParse(digits);
}

/// Compiles an unsigned legacy transfer from [account] to [destination].
///
/// [blockhash] and [lastValidBlockHeight] come from `getLatestBlockhash`.
/// The transaction is not signed. The fee payer is [account].
String buildUnsignedTipTransaction({
  required String account,
  required String destination,
  required BigInt lamports,
  required String blockhash,
  required BigInt lastValidBlockHeight,
}) {
  final payer = Address(account);
  final recipient = Address(destination);
  final instruction = getTransferSolInstruction(
    programAddress: systemProgramAddress,
    source: payer,
    destination: recipient,
    amount: lamports,
  );
  final message = createTransactionMessage(version: TransactionVersion.legacy)
      .withFeePayer(payer)
      .withBlockhashLifetime(
        BlockhashLifetimeConstraint(
          blockhash: blockhash,
          lastValidBlockHeight: lastValidBlockHeight,
        ),
      )
      .appendInstruction(instruction);
  return getBase64EncodedWireTransaction(compileTransaction(message));
}
