/// Shares a wallet and action client with every blink card below it.
library;

import 'package:flutter/widgets.dart';

import '../core/action_client.dart';
import '../core/transaction_executor.dart';
import '../wallet/blink_wallet_adapter.dart';
import 'blink_theme.dart';

/// Inherited wallet, client, and optional executor for blink cards.
///
/// Cards still accept their own adapter, client, and theme. Those arguments
/// win over this scope.
class BlinkScope extends InheritedWidget {
  /// Creates a scope.
  const BlinkScope({
    required this.wallet,
    required this.client,
    this.executor,
    this.theme,
    required super.child,
    super.key,
  });

  /// Wallet used by cards that do not receive their own adapter.
  final BlinkWalletAdapter wallet;

  /// Action client used by cards that do not receive their own client.
  final ActionClient client;

  /// Executor used by cards that do not receive their own executor.
  final TransactionExecutor? executor;

  /// Theme used by cards that do not receive their own theme.
  final BlinkTheme? theme;

  /// The nearest scope, or `null` when none is mounted.
  static BlinkScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BlinkScope>();
  }

  @override
  bool updateShouldNotify(BlinkScope oldWidget) {
    return wallet != oldWidget.wallet ||
        client != oldWidget.client ||
        executor != oldWidget.executor ||
        theme != oldWidget.theme;
  }
}
