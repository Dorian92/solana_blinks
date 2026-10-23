/// Flutter widgets for Solana Actions and Blinks.
///
/// Action models, [BlinkLinkParser], and [ActionClient] live in pure Dart and
/// do not import Flutter. Wallets are reached only through [BlinkWalletAdapter].
/// [BlinkCard] renders an action and executes it with the injected wallet.
library;

export 'src/core/action_client.dart';
export 'src/core/link_parser.dart';
export 'src/core/models.dart';
export 'src/core/transaction_executor.dart';
export 'src/version.dart';
export 'src/wallet/blink_wallet_adapter.dart';
export 'src/wallet/keypair_wallet_adapter.dart';
export 'src/wallet/mwa_wallet_adapter.dart';
export 'src/widgets/blink_card.dart';
export 'src/widgets/blink_controller.dart';
export 'src/widgets/blink_scope.dart';
export 'src/widgets/blink_theme.dart';
