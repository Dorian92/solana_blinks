/// Flutter widgets for Solana Actions and Blinks.
///
/// Action models, [BlinkLinkParser], and [ActionClient] live in pure Dart and
/// do not import Flutter. Wallets are reached only through [BlinkWalletAdapter].
library;

export 'src/core/action_client.dart';
export 'src/core/link_parser.dart';
export 'src/core/models.dart';
export 'src/version.dart';
export 'src/wallet/blink_wallet_adapter.dart';
