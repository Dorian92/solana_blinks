/// Immutable models for the Solana Actions specification.
///
/// JSON factories tolerate missing optional fields and ignore unknown fields.
/// Wire names that use dashes, such as `external-link`, are mapped onto Dart
/// identifiers.
library;

/// Kind of action a blink client should present.
///
/// [action], [completed], and [externalLink] are the values called out for
/// blink cards. [transaction], [post], and [message] are the linked-action
/// types from the Actions spec and are accepted so a response is not dropped
/// when a server sends them.
enum ActionType {
  /// A standard action the user can execute.
  action('action'),

  /// Terminal state of an action chain.
  completed('completed'),

  /// Opens [LinkedAction.href] outside the blink instead of posting.
  externalLink('external-link'),

  /// Linked action that returns a transaction. Same execution path as [action].
  transaction('transaction'),

  /// Linked action that asks the user to sign a message.
  message('message'),

  /// Linked action completed by a POST, with no transaction of its own.
  post('post');

  /// Creates a type from its spec wire value.
  const ActionType(this.wireValue);

  /// Value written to JSON, including dash-separated names.
  final String wireValue;

  /// Parses [raw], returning [fallback] when the value is missing or unknown.
  static ActionType parse(
    Object? raw, {
    ActionType fallback = ActionType.action,
  }) {
    if (raw is! String) {
      return fallback;
    }
    for (final type in ActionType.values) {
      if (type.wireValue == raw) {
        return type;
      }
    }
    return fallback;
  }
}

/// HTML-like input type for an [ActionParameter].
enum ActionParameterType {
  /// Single-line text. Also the fallback for a missing or unknown type.
  text('text'),

  /// Email address.
  email('email'),

  /// URL.
  url('url'),

  /// Number.
  number('number'),

  /// Calendar date (`YYYY-MM-DD`).
  date('date'),

  /// Local date and time.
  dateTimeLocal('datetime-local'),

  /// Multi-line text.
  textarea('textarea'),

  /// Single-choice dropdown.
  select('select'),

  /// Single-choice radio group.
  radio('radio'),

  /// Multi-choice checkbox group.
  checkbox('checkbox');

  /// Creates a parameter type from its spec wire value.
  const ActionParameterType(this.wireValue);

  /// Value written to JSON.
  final String wireValue;

  /// Whether this type presents [ActionParameter.options].
  bool get isSelectable =>
      this == ActionParameterType.select ||
      this == ActionParameterType.radio ||
      this == ActionParameterType.checkbox;

  /// Parses [raw], defaulting to [text] when the value is missing or unknown.
  static ActionParameterType parse(Object? raw) {
    if (raw is! String) {
      return ActionParameterType.text;
    }
    for (final type in ActionParameterType.values) {
      if (type.wireValue == raw) {
        return type;
      }
    }
    return ActionParameterType.text;
  }
}

/// One choice inside a select, radio, or checkbox parameter.
class ActionParameterOption {
  /// Creates an option.
  const ActionParameterOption({
    required this.label,
    required this.value,
    this.selected = false,
  });

  /// Label shown to the user.
  final String label;

  /// Value substituted into the action href.
  final String value;

  /// Whether the option starts selected.
  final bool selected;

  /// Parses an option, returning `null` when the object has no value.
  static ActionParameterOption? fromJson(Map<String, Object?> json) {
    final value = _asString(json['value']);
    if (value == null) {
      return null;
    }
    return ActionParameterOption(
      label: _asString(json['label']) ?? value,
      value: value,
      selected: _asBool(json['selected']) ?? false,
    );
  }

  /// Serializes this option.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'value': value,
    'selected': selected,
  };
}

/// User input declared by a [LinkedAction].
class ActionParameter {
  /// Creates a parameter.
  const ActionParameter({
    required this.name,
    this.label,
    this.required = false,
    this.type = ActionParameterType.text,
    this.pattern,
    this.patternDescription,
    this.min,
    this.max,
    this.options = const <ActionParameterOption>[],
  });

  /// Name used both as the `{name}` href placeholder and the form key.
  final String name;

  /// Placeholder or caption. Omitted servers leave this `null`.
  final String? label;

  /// Whether the field must be filled before the action can run.
  final bool required;

  /// Input widget to render.
  final ActionParameterType type;

  /// Regular expression, as a string, applied to the raw user input.
  final String? pattern;

  /// Human-readable description of [pattern], shown when validation fails.
  final String? patternDescription;

  /// Lower bound. A [num] for length or magnitude, or a [String] for dates.
  final Object? min;

  /// Upper bound. A [num] for length or magnitude, or a [String] for dates.
  final Object? max;

  /// Choices for [ActionParameterType.select], [ActionParameterType.radio],
  /// and [ActionParameterType.checkbox].
  final List<ActionParameterOption> options;

  /// Parses a parameter, returning `null` when [name] is missing.
  static ActionParameter? fromJson(Map<String, Object?> json) {
    final name = _asString(json['name']);
    if (name == null || name.isEmpty) {
      return null;
    }
    final options = <ActionParameterOption>[];
    final rawOptions = json['options'];
    if (rawOptions is List<Object?>) {
      for (final entry in rawOptions) {
        final map = _asMap(entry);
        if (map == null) {
          continue;
        }
        final option = ActionParameterOption.fromJson(map);
        if (option != null) {
          options.add(option);
        }
      }
    }
    return ActionParameter(
      name: name,
      label: _asString(json['label']),
      required: _asBool(json['required']) ?? false,
      type: ActionParameterType.parse(json['type']),
      pattern: _asString(json['pattern']),
      patternDescription: _asString(json['patternDescription']),
      min: _asBound(json['min']),
      max: _asBound(json['max']),
      options: List<ActionParameterOption>.unmodifiable(options),
    );
  }

  /// Serializes this parameter, omitting empty optional fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type.wireValue,
    'required': required,
    if (label != null) 'label': label,
    if (pattern != null) 'pattern': pattern,
    if (patternDescription != null) 'patternDescription': patternDescription,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (options.isNotEmpty)
      'options': options.map((option) => option.toJson()).toList(),
  };
}

/// Non-fatal or fatal error message from an Action endpoint.
class ActionError {
  /// Creates an error with the message shown to the user.
  const ActionError({required this.message});

  /// Message to display.
  final String message;

  /// Parses an error object. A bare string is accepted as the message.
  factory ActionError.fromJson(Object? json) {
    if (json is String) {
      return ActionError(message: json);
    }
    final map = _asMap(json);
    return ActionError(message: _asString(map?['message']) ?? '');
  }

  /// Serializes this error.
  Map<String, Object?> toJson() => <String, Object?>{'message': message};
}

/// One button, or button plus form, on an action.
class LinkedAction {
  /// Creates a linked action.
  const LinkedAction({
    required this.href,
    required this.label,
    this.type = ActionType.action,
    this.parameters = const <ActionParameter>[],
  });

  /// How the client should execute this action.
  final ActionType type;

  /// Absolute or relative URL the client posts to, or opens.
  final String href;

  /// Button label.
  final String label;

  /// Form fields collected before the request is sent.
  final List<ActionParameter> parameters;

  /// Whether this action opens [href] instead of posting.
  bool get isExternalLink => type == ActionType.externalLink;

  /// Parses a linked action. [href] and [label] fall back to empty strings.
  factory LinkedAction.fromJson(Map<String, Object?> json) {
    final parameters = <ActionParameter>[];
    final rawParameters = json['parameters'];
    if (rawParameters is List<Object?>) {
      for (final entry in rawParameters) {
        final map = _asMap(entry);
        if (map == null) {
          continue;
        }
        final parameter = ActionParameter.fromJson(map);
        if (parameter != null) {
          parameters.add(parameter);
        }
      }
    }
    return LinkedAction(
      type: ActionType.parse(json['type']),
      href: _asString(json['href']) ?? '',
      label: _asString(json['label']) ?? '',
      parameters: List<ActionParameter>.unmodifiable(parameters),
    );
  }

  /// Serializes this linked action.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.wireValue,
    'href': href,
    'label': label,
    if (parameters.isNotEmpty)
      'parameters': parameters.map((parameter) => parameter.toJson()).toList(),
  };
}

/// Metadata returned by `GET` on an Action URL.
class ActionGetResponse {
  /// Creates a GET response.
  const ActionGetResponse({
    required this.icon,
    required this.title,
    required this.description,
    required this.label,
    required this.actions,
    this.type = ActionType.action,
    this.disabled = false,
    this.error,
  });

  /// `action` for a normal blink, or [ActionType.completed] to end a chain.
  final ActionType type;

  /// Absolute URL of the icon. May be empty when the server omitted it.
  final String icon;

  /// Short title.
  final String title;

  /// Longer description shown under the title.
  final String description;

  /// Label of the default action. Not shown as its own button when [actions]
  /// came from `links.actions`.
  final String label;

  /// Whether every action on the card is disabled.
  final bool disabled;

  /// Non-fatal error the client should still display.
  final ActionError? error;

  /// Buttons to render. When the server omits `links.actions`, this contains
  /// one action whose href is [actionUrl] from [ActionGetResponse.fromJson].
  final List<LinkedAction> actions;

  /// Parses a GET body.
  ///
  /// [actionUrl] is the URL that was requested. It becomes the href of the
  /// single default action when `links.actions` is absent.
  factory ActionGetResponse.fromJson(
    Map<String, Object?> json, {
    String? actionUrl,
  }) {
    final label = _asString(json['label']) ?? '';
    final parsedActions = _parseActions(json['links']);
    final actions =
        parsedActions ??
        <LinkedAction>[LinkedAction(label: label, href: actionUrl ?? '')];
    final errorValue = json['error'];
    return ActionGetResponse(
      type: ActionType.parse(json['type']),
      icon: _asString(json['icon']) ?? '',
      title: _asString(json['title']) ?? '',
      description: _asString(json['description']) ?? '',
      label: label,
      disabled: _asBool(json['disabled']) ?? false,
      error: errorValue == null ? null : ActionError.fromJson(errorValue),
      actions: List<LinkedAction>.unmodifiable(actions),
    );
  }

  /// Serializes this response, always including `links.actions`.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.wireValue,
    'icon': icon,
    'title': title,
    'description': description,
    'label': label,
    'disabled': disabled,
    if (error != null) 'error': error!.toJson(),
    'links': <String, Object?>{
      'actions': actions.map((action) => action.toJson()).toList(),
    },
  };
}

/// Body posted to an Action URL.
class ActionPostRequest {
  /// Creates a POST body.
  ///
  /// [signature] is set only for an action-chaining callback.
  const ActionPostRequest({
    required this.account,
    this.signature,
    this.type,
    this.data,
  });

  /// Base58 public key of the account that may sign.
  final String account;

  /// Transaction signature from the previous action in a chain.
  final String? signature;

  /// Optional action type echoed to the server.
  final String? type;

  /// Optional parameter values. Multi-select values may be lists.
  final Map<String, Object?>? data;

  /// Parses a POST body.
  factory ActionPostRequest.fromJson(Map<String, Object?> json) {
    return ActionPostRequest(
      account: _asString(json['account']) ?? '',
      signature: _asString(json['signature']),
      type: _asString(json['type']),
      data: _asMap(json['data']),
    );
  }

  /// Serializes this request, omitting empty optional fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'account': account,
    if (signature != null) 'signature': signature,
    if (type != null) 'type': type,
    if (data != null) 'data': data,
  };
}

/// Either a callback POST or an action embedded in the POST response.
sealed class NextActionLink {
  /// Creates a next-action link.
  const NextActionLink();

  /// Parses `links.next`, returning `null` when the payload is unusable.
  static NextActionLink? fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) {
      return null;
    }
    final type = _asString(map['type']);
    if (type == 'inline' || map['action'] is Map) {
      final actionMap = _asMap(map['action']);
      if (actionMap == null) {
        return null;
      }
      return InlineNextActionLink(
        action: ActionGetResponse.fromJson(actionMap),
      );
    }
    final href = _asString(map['href']);
    if (href == null || href.isEmpty) {
      return null;
    }
    return PostNextActionLink(href: href);
  }

  /// Serializes this link.
  Map<String, Object?> toJson();
}

/// Callback the client POSTs after the previous transaction confirms.
class PostNextActionLink extends NextActionLink {
  /// Creates a post next-action link.
  const PostNextActionLink({required this.href});

  /// Relative or same-origin URL that receives `account` and `signature`.
  final String href;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'post',
    'href': href,
  };
}

/// Next action already included in the POST response.
class InlineNextActionLink extends NextActionLink {
  /// Creates an inline next-action link.
  const InlineNextActionLink({required this.action});

  /// Action to render after the previous transaction confirms.
  final ActionGetResponse action;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'inline',
    'action': action.toJson(),
  };
}

/// Body returned by `POST` on an Action URL.
class ActionPostResponse {
  /// Creates a POST response.
  const ActionPostResponse({
    this.transaction,
    this.message,
    this.next,
    this.type,
    this.externalLink,
  });

  /// Base64-encoded transaction, when this action asks for a signature.
  final String? transaction;

  /// Server message describing the transaction or the result.
  final String? message;

  /// Next action in a chain, when the server sent `links.next`.
  final NextActionLink? next;

  /// Response type when the server set one (`transaction`, `post`, ...).
  final ActionType? type;

  /// URL to open when [type] is [ActionType.externalLink].
  final String? externalLink;

  /// Parses a POST body.
  factory ActionPostResponse.fromJson(Map<String, Object?> json) {
    final links = _asMap(json['links']);
    return ActionPostResponse(
      transaction: _asString(json['transaction']),
      message: _asString(json['message']),
      next: links == null ? null : NextActionLink.fromJson(links['next']),
      type: json['type'] == null ? null : ActionType.parse(json['type']),
      externalLink: _asString(json['externalLink']),
    );
  }

  /// Serializes this response.
  Map<String, Object?> toJson() => <String, Object?>{
    if (type != null) 'type': type!.wireValue,
    if (transaction != null) 'transaction': transaction,
    if (message != null) 'message': message,
    if (externalLink != null) 'externalLink': externalLink,
    if (next != null) 'links': <String, Object?>{'next': next!.toJson()},
  };
}

List<LinkedAction>? _parseActions(Object? links) {
  final map = _asMap(links);
  if (map == null || !map.containsKey('actions')) {
    return null;
  }
  final rawActions = map['actions'];
  if (rawActions is! List<Object?>) {
    return null;
  }
  final actions = <LinkedAction>[];
  for (final entry in rawActions) {
    final actionMap = _asMap(entry);
    if (actionMap == null) {
      continue;
    }
    actions.add(LinkedAction.fromJson(actionMap));
  }
  return actions;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? nested) => MapEntry(key.toString(), nested),
    );
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

Object? _asBound(Object? value) {
  if (value is num || value is String) {
    return value;
  }
  return null;
}
