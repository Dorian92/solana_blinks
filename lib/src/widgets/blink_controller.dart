/// State machine for loading and executing a blink.
library;

import 'package:flutter/foundation.dart';

import '../core/action_client.dart';
import '../core/link_parser.dart';
import '../core/models.dart';
import '../core/transaction_executor.dart';
import '../wallet/blink_wallet_adapter.dart';

/// Phase of a blink card.
enum BlinkPhase {
  /// The action URL is being resolved or fetched.
  loading,

  /// Metadata is visible and actions can be submitted.
  ready,

  /// A wallet prompt or confirmation is in progress.
  executing,

  /// The transaction confirmed, or a chained action completed.
  success,

  /// The last load or execution failed.
  error,
}

/// Owns the blink state machine.
///
/// The card listens to this object. Pass one in when several widgets should
/// share a load, or let the card create one from the injected client, wallet,
/// and executor.
class BlinkController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [linkParser] defaults to a parser that uses [client]'s HTTP client when
  /// that client was injected on [ActionClient].
  BlinkController({
    required this.client,
    required this.wallet,
    required this.executor,
    BlinkLinkParser? linkParser,
  }) : _linkParser =
           linkParser ?? BlinkLinkParser(httpClient: client.httpClient);

  /// Client that fetches metadata and posts the account.
  final ActionClient client;

  /// Wallet that signs the action transaction.
  final BlinkWalletAdapter wallet;

  /// Executor that submits the signed transaction.
  final TransactionExecutor executor;

  final BlinkLinkParser _linkParser;

  /// Current phase.
  BlinkPhase phase = BlinkPhase.loading;

  /// Metadata on screen, once a load has succeeded.
  ActionGetResponse? action;

  /// Action URL used to resolve relative hrefs.
  Uri? actionUrl;

  /// Non-fatal action error, or the latest failure.
  String? errorMessage;

  /// Server message from the POST response.
  String? successMessage;

  /// Confirmed transaction signature.
  String? signature;

  /// Whether [action] was loaded from `links.next`.
  bool chained = false;

  bool _disposed = false;

  /// Resolves [input] and fetches its action.
  Future<void> open(String input) async {
    phase = BlinkPhase.loading;
    errorMessage = null;
    successMessage = null;
    signature = null;
    chained = false;
    _notify();
    try {
      final resolved = await _linkParser.parse(input);
      if (resolved == null) {
        _fail('This URL is not a Solana Action.');
        return;
      }
      final fetched = await client.fetchAction(resolved);
      action = fetched;
      actionUrl = resolved;
      errorMessage = fetched.error?.message;
      phase = BlinkPhase.ready;
    } on BlinkException catch (error) {
      _fail(error.message);
      return;
    } on Object catch (error) {
      _fail('$error');
      return;
    }
    _notify();
  }

  /// Shows [value] without fetching it.
  ///
  /// [baseUrl] is the origin used for relative hrefs.
  void present(ActionGetResponse value, {Uri? baseUrl}) {
    action = value;
    actionUrl = baseUrl;
    errorMessage = value.error?.message;
    successMessage = null;
    signature = null;
    chained = false;
    phase = value.type == ActionType.completed
        ? BlinkPhase.success
        : BlinkPhase.ready;
    _notify();
  }

  /// Connects the wallet if needed, posts [linked], and confirms it.
  ///
  /// Returns the signature when the transaction confirms, including when a
  /// next action is then shown. Returns `null` when the user rejects the
  /// wallet or the action fails.
  Future<String?> execute(
    LinkedAction linked,
    Map<String, String> values,
  ) async {
    if (phase == BlinkPhase.executing) {
      return null;
    }
    if (linked.isExternalLink) {
      return null;
    }
    final base = actionUrl;
    phase = BlinkPhase.executing;
    errorMessage = null;
    _notify();
    try {
      var account = wallet.publicKey;
      account ??= await wallet.connect();
      if (account == null || account.isEmpty) {
        _fail('The wallet did not return an account.');
        return null;
      }
      var href = linked.href;
      if (href.isEmpty && base != null) {
        href = base.toString();
      }
      final target = client.resolveHref(href, values, base);
      final posted = await client.postAction(target, account);
      final result = await executor.execute(posted);
      switch (result) {
        case ExecutionSuccess(:final signature):
          this.signature = signature;
          successMessage = posted.message;
          if (posted.next == null) {
            phase = BlinkPhase.success;
            _notify();
            return signature;
          }
          final next = await client.followNext(posted, signature);
          action = next;
          chained = true;
          errorMessage = next.error?.message;
          phase = next.type == ActionType.completed
              ? BlinkPhase.success
              : BlinkPhase.ready;
          _notify();
          return signature;
        case ExecutionFailure(:final reason):
          _fail(reason);
          return null;
      }
    } on BlinkException catch (error) {
      _fail(error.message);
      return null;
    } on WalletException catch (error) {
      _fail(error.message);
      return null;
    } on Object catch (error) {
      _fail('$error');
      return null;
    }
  }

  /// Resolves an external-link href against [actionUrl].
  Uri? externalTarget(LinkedAction linked, Map<String, String> values) {
    if (!linked.isExternalLink) {
      return null;
    }
    try {
      var href = linked.href;
      if (href.isEmpty && actionUrl != null) {
        href = actionUrl.toString();
      }
      return client.resolveHref(href, values, actionUrl);
    } on BlinkException {
      return null;
    }
  }

  void _fail(String message) {
    errorMessage = message;
    phase = BlinkPhase.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Validates one action parameter.
///
/// Returns an error message, or `null` when [value] is acceptable. An invalid
/// [ActionParameter.pattern] is ignored, matching the Actions spec.
String? validateActionParameter(ActionParameter parameter, String value) {
  final trimmed = value.trim();
  final label = parameter.label ?? parameter.name;
  if (parameter.required && trimmed.isEmpty) {
    return '$label is required.';
  }
  if (trimmed.isEmpty) {
    return null;
  }

  final pattern = parameter.pattern;
  if (pattern != null && pattern.isNotEmpty) {
    try {
      if (!RegExp(pattern).hasMatch(trimmed)) {
        return parameter.patternDescription ?? 'Enter a valid $label.';
      }
    } on FormatException {
      // The spec says to ignore a pattern that is not a valid expression.
    }
  }

  switch (parameter.type) {
    case ActionParameterType.email:
      if (!trimmed.contains('@')) {
        return 'Enter a valid email.';
      }
    case ActionParameterType.url:
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null || !parsed.hasScheme) {
        return 'Enter a valid URL.';
      }
    case ActionParameterType.number:
      final number = num.tryParse(trimmed);
      if (number == null) {
        return 'Enter a number.';
      }
      final minimum = parameter.min;
      final maximum = parameter.max;
      if (minimum is num && number < minimum) {
        return 'Must be at least $minimum.';
      }
      if (maximum is num && number > maximum) {
        return 'Must be at most $maximum.';
      }
    case ActionParameterType.date:
    case ActionParameterType.dateTimeLocal:
      final minimum = parameter.min;
      final maximum = parameter.max;
      if (minimum is String && trimmed.compareTo(minimum) < 0) {
        return 'Must be on or after $minimum.';
      }
      if (maximum is String && trimmed.compareTo(maximum) > 0) {
        return 'Must be on or before $maximum.';
      }
    case ActionParameterType.text:
    case ActionParameterType.textarea:
      final minimum = parameter.min;
      final maximum = parameter.max;
      if (minimum is num && trimmed.length < minimum) {
        return 'Must be at least $minimum characters.';
      }
      if (maximum is num && trimmed.length > maximum) {
        return 'Must be at most $maximum characters.';
      }
    case ActionParameterType.select:
    case ActionParameterType.radio:
    case ActionParameterType.checkbox:
      break;
  }
  return null;
}
