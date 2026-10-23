/// Blink card that loads an action and executes it with an injected wallet.
library;

import 'package:flutter/material.dart';

import '../core/action_client.dart';
import '../core/link_parser.dart';
import '../core/models.dart';
import '../core/transaction_executor.dart';
import '../wallet/blink_wallet_adapter.dart';
import 'blink_controller.dart';
import 'blink_scope.dart';
import 'blink_theme.dart';

/// Cluster endpoint used when a card builds its own executor.
const String defaultBlinkRpcUrl = 'https://api.devnet.solana.com';

/// Separator stored between selected checkbox values.
const String _checkboxSeparator = '\u001f';

/// Renders one Solana Action and runs it when the user submits.
///
/// Pass [url] or a pre-resolved [action]. An explicit [adapter], [client],
/// [executor], and [theme] win over the surrounding [BlinkScope]. When
/// [controller] is omitted, the card creates one and disposes it.
///
/// The first successful submit connects [adapter] when it has no public key.
class BlinkCard extends StatefulWidget {
  /// Creates a card for [url] or [action].
  ///
  /// When both are set, [action] is shown and [url] is not fetched.
  const BlinkCard({
    super.key,
    this.url,
    this.action,
    this.baseUrl,
    this.adapter,
    this.client,
    this.executor,
    this.controller,
    this.theme,
    this.rpcUrl,
    this.linkParser,
    this.onSuccess,
    this.onError,
    this.onExternalLink,
  }) : assert(url != null || action != null, 'Pass a url or an action.');

  /// Blink URL passed to [BlinkLinkParser] when [action] is null.
  final String? url;

  /// Metadata to show without a GET.
  final ActionGetResponse? action;

  /// Origin used to resolve relative hrefs for [action].
  final Uri? baseUrl;

  /// Wallet that signs the transaction.
  ///
  /// Falls back to [BlinkScope.wallet].
  final BlinkWalletAdapter? adapter;

  /// Client that fetches and posts the action.
  ///
  /// Falls back to [BlinkScope.client].
  final ActionClient? client;

  /// Executor that confirms the transaction.
  ///
  /// Falls back to [BlinkScope.executor], then to an executor aimed at
  /// [rpcUrl] or [defaultBlinkRpcUrl].
  final TransactionExecutor? executor;

  /// State machine to listen to.
  ///
  /// When null, the card creates a [BlinkController] from [client], [adapter],
  /// and [executor], and disposes it.
  final BlinkController? controller;

  /// Colors and text styles.
  ///
  /// Falls back to [BlinkScope.theme], then to [BlinkTheme.fromMaterial].
  final BlinkTheme? theme;

  /// RPC URL used only when the card builds its own executor.
  final String? rpcUrl;

  /// Parser used only when the card builds its own controller.
  final BlinkLinkParser? linkParser;

  /// Called with the confirmed signature.
  final ValueChanged<String>? onSuccess;

  /// Called with the message when a load or execution fails.
  final ValueChanged<Object>? onError;

  /// Called with the resolved URL of an external-link action.
  final ValueChanged<Uri>? onExternalLink;

  @override
  State<BlinkCard> createState() => _BlinkCardState();
}

class _BlinkCardState extends State<BlinkCard> {
  BlinkController? _owned;
  BlinkTheme? _scopeTheme;
  String? _loadedKey;
  ActionGetResponse? _seenAction;
  String? _reportedSignature;
  String? _reportedError;
  final Map<String, String> _values = <String, String>{};
  Map<String, String> _fieldErrors = <String, String>{};

  BlinkController? get _active => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = BlinkScope.maybeOf(context);
    _scopeTheme = scope?.theme;
    _bind(scope);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(BlinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onController);
      if (widget.controller != null) {
        _owned?.removeListener(_onController);
        _owned?.dispose();
        _owned = null;
        widget.controller!.addListener(_onController);
      }
      _loadedKey = null;
    } else if (oldWidget.url != widget.url ||
        !identical(oldWidget.action, widget.action) ||
        oldWidget.baseUrl != widget.baseUrl) {
      _loadedKey = null;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _owned?.removeListener(_onController);
    _owned?.dispose();
    super.dispose();
  }

  void _bind(BlinkScope? scope) {
    if (widget.controller != null || _owned != null) {
      return;
    }
    final wallet = widget.adapter ?? scope?.wallet;
    final client = widget.client ?? scope?.client;
    if (wallet == null || client == null) {
      return;
    }
    final executor =
        widget.executor ??
        scope?.executor ??
        TransactionExecutor(
          wallet: wallet,
          rpcUrl: widget.rpcUrl ?? defaultBlinkRpcUrl,
        );
    _owned = BlinkController(
      client: client,
      wallet: wallet,
      executor: executor,
      linkParser: widget.linkParser,
    )..addListener(_onController);
  }

  void _ensureLoaded() {
    final controller = _active;
    if (controller == null) {
      return;
    }
    final key = widget.action != null
        ? 'action:${identityHashCode(widget.action)}:${widget.baseUrl}'
        : 'url:${widget.url}';
    if (_loadedKey == key) {
      return;
    }
    _loadedKey = key;
    _values.clear();
    _fieldErrors = <String, String>{};
    final action = widget.action;
    if (action != null) {
      controller.present(action, baseUrl: widget.baseUrl);
    } else {
      final url = widget.url;
      if (url != null) {
        controller.open(url);
      }
    }
  }

  void _onController() {
    final controller = _active;
    if (controller == null) {
      return;
    }
    if (!identical(controller.action, _seenAction)) {
      _seenAction = controller.action;
      _values.clear();
      _fieldErrors = <String, String>{};
    }
    switch (controller.phase) {
      case BlinkPhase.success:
        _reportedError = null;
        final signature = controller.signature;
        if (signature != null && signature != _reportedSignature) {
          _reportedSignature = signature;
          widget.onSuccess?.call(signature);
        }
      case BlinkPhase.error:
        final message = controller.errorMessage;
        if (message != null && message != _reportedError) {
          _reportedError = message;
          widget.onError?.call(message);
        }
      case BlinkPhase.loading:
      case BlinkPhase.ready:
      case BlinkPhase.executing:
        _reportedError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        widget.theme ??
        _scopeTheme ??
        BlinkTheme.fromMaterial(Theme.of(context));
    final controller = _active;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Material(
          color: theme.background,
          elevation: 1,
          borderRadius: BorderRadius.circular(theme.radius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: controller == null
                  ? Text(
                      'Pass a wallet and an action client, or wrap the card in a BlinkScope.',
                      style: theme.body.copyWith(color: theme.error),
                    )
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => _body(theme, controller),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BlinkTheme theme, BlinkController controller) {
    final action = controller.action;
    if (action == null) {
      if (controller.phase == BlinkPhase.error) {
        return Text(
          controller.errorMessage ?? 'This blink could not be loaded.',
          key: const Key('blink-error'),
          style: theme.body.copyWith(color: theme.error),
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(key: Key('blink-loading')),
        ),
      );
    }

    final host = controller.actionUrl?.host ?? '';
    final blocked = _blocked(controller, action);
    final showActions =
        controller.phase != BlinkPhase.success &&
        action.type != ActionType.completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _icon(action, theme),
        const SizedBox(height: 12),
        Text(
          action.title,
          key: const Key('blink-title'),
          style: theme.title.copyWith(color: theme.foreground),
        ),
        if (action.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            action.description,
            style: theme.body.copyWith(color: theme.muted),
          ),
        ],
        if (host.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            host,
            key: const Key('blink-host'),
            style: theme.caption.copyWith(color: theme.muted),
          ),
        ],
        if ((controller.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            controller.errorMessage!,
            key: const Key('blink-error'),
            style: theme.body.copyWith(color: theme.error),
          ),
        ],
        if (controller.phase == BlinkPhase.executing)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  key: Key('blink-executing'),
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        if (controller.phase == BlinkPhase.success) ...[
          if ((controller.successMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              controller.successMessage!,
              key: const Key('blink-message'),
              style: theme.body.copyWith(color: theme.success),
            ),
          ],
          if ((controller.signature ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              controller.signature!,
              key: const Key('blink-signature'),
              style: theme.caption.copyWith(color: theme.muted),
            ),
          ],
        ],
        if (showActions) ..._actionSections(theme, controller, action, blocked),
      ],
    );
  }

  bool _blocked(BlinkController controller, ActionGetResponse action) {
    return action.disabled ||
        controller.phase == BlinkPhase.executing ||
        action.type == ActionType.completed;
  }

  Widget _icon(ActionGetResponse action, BlinkTheme theme) {
    final icon = action.icon.trim();
    final placeholder = ColoredBox(
      color: theme.accent.withValues(alpha: 0.12),
      child: Icon(Icons.bolt, color: theme.accent, size: 48),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.radius - 4),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: icon.isEmpty
            ? placeholder
            : Image.network(
                icon,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }

  List<Widget> _actionSections(
    BlinkTheme theme,
    BlinkController controller,
    ActionGetResponse action,
    bool blocked,
  ) {
    final plain = <Widget>[];
    final forms = <Widget>[];
    for (var index = 0; index < action.actions.length; index++) {
      final linked = action.actions[index];
      if (linked.parameters.isEmpty) {
        plain.add(_button(theme, controller, linked, index, blocked));
      } else {
        forms.add(_form(theme, controller, linked, index, blocked));
      }
    }
    return [
      if (plain.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: plain),
      ],
      ...forms,
    ];
  }

  Widget _button(
    BlinkTheme theme,
    BlinkController controller,
    LinkedAction linked,
    int index,
    bool blocked,
  ) {
    return FilledButton(
      key: Key('blink-action-${linked.label}'),
      style: FilledButton.styleFrom(
        backgroundColor: theme.accent,
        foregroundColor: theme.onAccent,
        textStyle: theme.label,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radius),
        ),
      ),
      onPressed: blocked ? null : () => _submit(controller, linked, index),
      child: Text(linked.label),
    );
  }

  Widget _form(
    BlinkTheme theme,
    BlinkController controller,
    LinkedAction linked,
    int index,
    bool blocked,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final parameter in linked.parameters) ...[
            _parameter(theme, parameter, index, blocked),
            const SizedBox(height: 8),
          ],
          _button(theme, controller, linked, index, blocked),
        ],
      ),
    );
  }

  Widget _parameter(
    BlinkTheme theme,
    ActionParameter parameter,
    int index,
    bool blocked,
  ) {
    final storageKey = _storageKey(index, parameter.name);
    final current = _read(index, parameter);
    final error = _fieldErrors[storageKey];
    final label = parameter.label ?? parameter.name;
    switch (parameter.type) {
      case ActionParameterType.select:
        return _select(theme, parameter, storageKey, current, error, blocked);
      case ActionParameterType.radio:
        return _choices(
          theme,
          parameter,
          storageKey,
          current,
          error,
          blocked,
          label,
          radios: true,
        );
      case ActionParameterType.checkbox:
        return _choices(
          theme,
          parameter,
          storageKey,
          current,
          error,
          blocked,
          label,
          radios: false,
        );
      case ActionParameterType.text:
      case ActionParameterType.email:
      case ActionParameterType.url:
      case ActionParameterType.number:
      case ActionParameterType.date:
      case ActionParameterType.dateTimeLocal:
      case ActionParameterType.textarea:
        return TextFormField(
          key: Key('blink-param-${parameter.name}'),
          initialValue: current,
          enabled: !blocked,
          keyboardType: _keyboard(parameter.type),
          minLines: parameter.type == ActionParameterType.textarea ? 3 : 1,
          maxLines: parameter.type == ActionParameterType.textarea ? 6 : 1,
          style: theme.body.copyWith(color: theme.foreground),
          decoration: InputDecoration(labelText: label, errorText: error),
          onChanged: (value) => _write(storageKey, value),
        );
    }
  }

  Widget _select(
    BlinkTheme theme,
    ActionParameter parameter,
    String storageKey,
    String current,
    String? error,
    bool blocked,
  ) {
    final known = parameter.options.any((option) => option.value == current);
    return DropdownButtonFormField<String>(
      key: Key('blink-param-${parameter.name}'),
      initialValue: known ? current : null,
      items: [
        for (final option in parameter.options)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      onChanged: blocked
          ? null
          : (value) {
              if (value != null) {
                _write(storageKey, value);
              }
            },
      decoration: InputDecoration(
        labelText: parameter.label ?? parameter.name,
        errorText: error,
      ),
    );
  }

  Widget _choices(
    BlinkTheme theme,
    ActionParameter parameter,
    String storageKey,
    String current,
    String? error,
    bool blocked,
    String label, {
    required bool radios,
  }) {
    final selected = radios
        ? <String>{if (current.isNotEmpty) current}
        : current
              .split(_checkboxSeparator)
              .where((part) => part.isNotEmpty)
              .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.label.copyWith(color: theme.foreground)),
        if (radios)
          RadioGroup<String>(
            groupValue: current.isEmpty ? null : current,
            onChanged: (value) {
              if (blocked || value == null) {
                return;
              }
              _write(storageKey, value);
            },
            child: Column(
              children: [
                for (final option in parameter.options)
                  RadioListTile<String>(
                    key: Key('blink-param-${parameter.name}-${option.value}'),
                    value: option.value,
                    title: Text(option.label),
                    contentPadding: EdgeInsets.zero,
                    enabled: !blocked,
                    activeColor: theme.accent,
                  ),
              ],
            ),
          )
        else
          for (final option in parameter.options)
            CheckboxListTile(
              key: Key('blink-param-${parameter.name}-${option.value}'),
              value: selected.contains(option.value),
              title: Text(option.label),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: theme.accent,
              onChanged: blocked
                  ? null
                  : (checked) {
                      final next = Set<String>.of(selected);
                      if (checked ?? false) {
                        next.add(option.value);
                      } else {
                        next.remove(option.value);
                      }
                      _write(storageKey, next.join(_checkboxSeparator));
                    },
            ),
        if (error != null)
          Text(
            error,
            key: Key('blink-param-error-${parameter.name}'),
            style: theme.caption.copyWith(color: theme.error),
          ),
      ],
    );
  }

  TextInputType _keyboard(ActionParameterType type) {
    switch (type) {
      case ActionParameterType.email:
        return TextInputType.emailAddress;
      case ActionParameterType.url:
        return TextInputType.url;
      case ActionParameterType.number:
        return TextInputType.number;
      case ActionParameterType.date:
      case ActionParameterType.dateTimeLocal:
        return TextInputType.datetime;
      case ActionParameterType.textarea:
        return TextInputType.multiline;
      case ActionParameterType.text:
      case ActionParameterType.select:
      case ActionParameterType.radio:
      case ActionParameterType.checkbox:
        return TextInputType.text;
    }
  }

  Future<void> _submit(
    BlinkController controller,
    LinkedAction linked,
    int index,
  ) async {
    final values = <String, String>{};
    final errors = <String, String>{};
    for (final parameter in linked.parameters) {
      final storageKey = _storageKey(index, parameter.name);
      final raw = _values[storageKey] ?? _initialValue(parameter);
      final submitted = _submittedValue(parameter, raw);
      final message = validateActionParameter(parameter, submitted);
      if (message != null) {
        errors[storageKey] = message;
      }
      values[parameter.name] = submitted;
    }
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }
    if (_fieldErrors.isNotEmpty) {
      setState(() => _fieldErrors = <String, String>{});
    }
    if (linked.isExternalLink) {
      final target = controller.externalTarget(linked, values);
      if (target != null) {
        widget.onExternalLink?.call(target);
      }
      return;
    }
    await controller.execute(linked, values);
  }

  String _read(int index, ActionParameter parameter) {
    final key = _storageKey(index, parameter.name);
    return _values.putIfAbsent(key, () => _initialValue(parameter));
  }

  void _write(String key, String value) {
    setState(() {
      _values[key] = value;
      _fieldErrors.remove(key);
    });
  }

  String _storageKey(int index, String name) => '$index:$name';

  String _initialValue(ActionParameter parameter) {
    final selected = <String>[
      for (final option in parameter.options)
        if (option.selected) option.value,
    ];
    switch (parameter.type) {
      case ActionParameterType.checkbox:
        return selected.join(_checkboxSeparator);
      case ActionParameterType.radio:
      case ActionParameterType.select:
        if (selected.isEmpty) {
          return '';
        }
        return selected.first;
      case ActionParameterType.text:
      case ActionParameterType.email:
      case ActionParameterType.url:
      case ActionParameterType.number:
      case ActionParameterType.date:
      case ActionParameterType.dateTimeLocal:
      case ActionParameterType.textarea:
        return '';
    }
  }

  String _submittedValue(ActionParameter parameter, String raw) {
    if (parameter.type == ActionParameterType.checkbox) {
      return raw
          .split(_checkboxSeparator)
          .where((part) => part.isNotEmpty)
          .join(',');
    }
    return raw.trim();
  }
}
