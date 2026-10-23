/// HTTP client for the Solana Actions `GET` and `POST` flow.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Default `User-Agent` sent on Action requests.
const String actionClientUserAgent = 'solana_blinks/0.1.0';

/// Failure returned by an Action endpoint, or by the client before a request.
class BlinkException implements Exception {
  /// Creates an exception with a message safe to show in a blink card.
  const BlinkException(this.message, {this.statusCode, this.uri});

  /// Message to display.
  final String message;

  /// HTTP status when the failure came from a response.
  final int? statusCode;

  /// URL that failed, when one was requested.
  final Uri? uri;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'BlinkException$status: $message';
  }
}

/// Calls Action URLs and resolves their href templates.
class ActionClient {
  /// Creates a client.
  ///
  /// [httpClient] is reused for every request when it is provided. Otherwise
  /// each request opens and closes its own client.
  ActionClient({
    this.httpClient,
    this.timeout = const Duration(seconds: 20),
    this.userAgent = actionClientUserAgent,
  });

  /// Injected HTTP client, or `null` to create one per request.
  final http.Client? httpClient;

  /// How long a single Action request may take.
  final Duration timeout;

  /// `User-Agent` header sent with every request.
  final String userAgent;

  Uri? _actionUrl;
  String? _account;

  /// GETs [url] and parses the Action metadata.
  ///
  /// The requested URL is stored and used as the base for later relative
  /// hrefs, and as the href of the default action when the body omits
  /// `links.actions`.
  Future<ActionGetResponse> fetchAction(Uri url) async {
    final response = await _send(url, method: 'GET');
    _actionUrl = url;
    return ActionGetResponse.fromJson(
      _decodeObject(response),
      actionUrl: url.toString(),
    );
  }

  /// Fills `{name}` placeholders in [href] and resolves a relative href.
  ///
  /// Values are percent-encoded. Relative hrefs are resolved against the
  /// origin of [baseUrl], or against the most recent [fetchAction] or
  /// [postAction] URL when [baseUrl] is omitted.
  ///
  /// Throws a [BlinkException] when a placeholder has no value, or when a
  /// relative href has no base URL.
  Uri resolveHref(String href, Map<String, String> values, [Uri? baseUrl]) {
    final substituted = href.replaceAllMapped(_placeholder, (match) {
      final name = match.group(1)!;
      final value = values[name];
      if (value == null) {
        throw BlinkException('Missing a value for {$name}.');
      }
      return Uri.encodeComponent(value);
    });

    final parsed = Uri.tryParse(substituted);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    final base = baseUrl ?? _actionUrl;
    if (base == null) {
      throw BlinkException(
        'Cannot resolve relative href "$href" without an action URL.',
      );
    }
    return _origin(base).resolve(substituted);
  }

  /// POSTs [account] to [url] and parses the transaction response.
  ///
  /// [account] and [url] are remembered for [followNext].
  Future<ActionPostResponse> postAction(Uri url, String account) async {
    _actionUrl = url;
    _account = account;
    final response = await _send(
      url,
      method: 'POST',
      body: ActionPostRequest(account: account).toJson(),
    );
    return ActionPostResponse.fromJson(_decodeObject(response));
  }

  /// Loads the next action after [signature] confirms.
  ///
  /// A [PostNextActionLink] is POSTed `account` and [signature], and only when
  /// the callback is the same origin as the action that was just posted. An
  /// [InlineNextActionLink] returns its embedded action with no request.
  ///
  /// The account is the one passed to the most recent [postAction].
  Future<ActionGetResponse> followNext(
    ActionPostResponse response,
    String signature,
  ) async {
    final next = response.next;
    switch (next) {
      case null:
        throw const BlinkException('The action did not include a next link.');
      case InlineNextActionLink(:final action):
        return action;
      case PostNextActionLink(:final href):
        final base = _actionUrl;
        final account = _account;
        if (base == null || account == null || account.isEmpty) {
          throw const BlinkException(
            'Follow a posted action before requesting the next one.',
          );
        }
        final callback = resolveHref(href, const <String, String>{});
        if (!_sameOrigin(callback, base)) {
          throw BlinkException(
            'Refusing to send the signature to ${callback.host}.',
            uri: callback,
          );
        }
        final body = await _send(
          callback,
          method: 'POST',
          body: ActionPostRequest(
            account: account,
            signature: signature,
          ).toJson(),
        );
        return ActionGetResponse.fromJson(
          _decodeObject(body),
          actionUrl: callback.toString(),
        );
    }
  }

  Future<http.Response> _send(
    Uri url, {
    required String method,
    Map<String, Object?>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Encoding': 'identity',
      'User-Agent': userAgent,
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    final encoded = body == null ? null : jsonEncode(body);

    try {
      final response = await _dispatch(
        method: method,
        url: url,
        headers: headers,
        body: encoded,
      ).timeout(timeout);
      _throwIfNotOk(response);
      return response;
    } on BlinkException {
      rethrow;
    } on TimeoutException {
      throw BlinkException('The action request to $url timed out.', uri: url);
    } on http.ClientException catch (error) {
      throw BlinkException(error.message, uri: url);
    }
  }

  Future<http.Response> _dispatch({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required String? body,
  }) {
    final client = httpClient;
    if (client != null) {
      return _request(client, method, url, headers, body);
    }
    final owned = http.Client();
    return _request(
      owned,
      method,
      url,
      headers,
      body,
    ).whenComplete(owned.close);
  }

  Future<http.Response> _request(
    http.Client client,
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) {
    if (method == 'POST') {
      return client.post(url, headers: headers, body: body);
    }
    return client.get(url, headers: headers);
  }

  void _throwIfNotOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw BlinkException(
      _errorMessage(response),
      statusCode: response.statusCode,
      uri: response.request?.url ?? _actionUrl,
    );
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } on FormatException {
      // Fall through to the status line.
    }
    final body = response.body.trim();
    if (body.isEmpty) {
      return 'Action request failed (${response.statusCode}).';
    }
    return 'Action request failed (${response.statusCode}): $body';
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw BlinkException(
        'The action response was not valid JSON.',
        statusCode: response.statusCode,
        uri: response.request?.url,
      );
    }
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
    throw BlinkException(
      'The action response was not a JSON object.',
      statusCode: response.statusCode,
      uri: response.request?.url,
    );
  }
}

final RegExp _placeholder = RegExp(r'\{([^{}]+)\}');

Uri _origin(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/',
  );
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;
