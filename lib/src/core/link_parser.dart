/// Resolves a blink URL to the Action API URL the client should GET.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Default `User-Agent` sent when fetching `actions.json`.
const String blinkLinkParserUserAgent = 'solana_blinks/0.1.0';

/// Resolves blink URLs to Action API URLs.
///
/// Three inputs are understood:
///
/// * a `solana-action:` URL
/// * an `https` website URL whose `action` query parameter is a URL-encoded
///   Action URL (the dial.to interstitial shape)
/// * a plain website URL, mapped through `https://host/actions.json`
///
/// `actions.json` rules support exact paths plus `*` (one segment) and `**`
/// (the rest of the path, including slashes). Query parameters on the website
/// URL are copied onto the mapped Action URL.
class BlinkLinkParser {
  /// Creates a parser.
  ///
  /// [httpClient] is used for `actions.json`. When it is omitted, a client is
  /// created for that single request and closed afterwards.
  BlinkLinkParser({
    this.httpClient,
    this.timeout = const Duration(seconds: 15),
    this.userAgent = blinkLinkParserUserAgent,
  });

  /// Client used for `actions.json`. `null` creates one per request.
  final http.Client? httpClient;

  /// How long an `actions.json` fetch may take.
  final Duration timeout;

  /// `User-Agent` header sent with `actions.json` requests.
  final String userAgent;

  /// Returns the Action API URL for [input], or `null` when it cannot be
  /// resolved.
  Future<Uri?> parse(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('solana-action:')) {
      return _parseSolanaAction(trimmed);
    }

    final website = Uri.tryParse(trimmed);
    if (website == null || !_isHttp(website)) {
      return null;
    }

    final actionParameter = website.queryParameters['action'];
    if (actionParameter != null && actionParameter.isNotEmpty) {
      if (actionParameter.startsWith('solana-action:')) {
        return _parseSolanaAction(actionParameter);
      }
      final actionUrl = Uri.tryParse(actionParameter);
      if (actionUrl != null && _isHttp(actionUrl)) {
        return actionUrl;
      }
      return null;
    }

    return _resolveFromActionsJson(website);
  }

  /// Applies one `actions.json` rule.
  ///
  /// Returns `null` when [websiteUrl] does not match [pathPattern].
  static Uri? mapRule({
    required Uri websiteUrl,
    required String pathPattern,
    required String apiPath,
  }) {
    final subject = _matchSubject(websiteUrl, pathPattern);
    final match = _compilePattern(pathPattern).firstMatch(subject);
    if (match == null) {
      return null;
    }

    final captures = <String>[
      for (var group = 1; group <= match.groupCount; group++)
        match.group(group) ?? '',
    ];
    var captureIndex = 0;
    final replaced = apiPath.replaceAllMapped(RegExp(r'\*\*|\*'), (wildcard) {
      if (captureIndex >= captures.length) {
        return '';
      }
      return captures[captureIndex++];
    });

    final Uri mapped;
    final absolute = Uri.tryParse(replaced);
    if (absolute != null && absolute.hasScheme && _isHttp(absolute)) {
      mapped = absolute;
    } else {
      final path = replaced.startsWith('/') ? replaced : '/$replaced';
      mapped = _origin(websiteUrl).replace(path: path);
    }
    return _copyQuery(mapped, websiteUrl);
  }

  Future<Uri?> _resolveFromActionsJson(Uri website) async {
    final actionsJsonUrl = _origin(website).replace(path: '/actions.json');
    try {
      final response = await _get(actionsJsonUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final rules = decoded['rules'];
      if (rules is! List<Object?>) {
        return null;
      }
      for (final rule in rules) {
        if (rule is! Map) {
          continue;
        }
        final pathPattern = rule['pathPattern'];
        final apiPath = rule['apiPath'];
        if (pathPattern is! String || apiPath is! String) {
          continue;
        }
        final mapped = mapRule(
          websiteUrl: website,
          pathPattern: pathPattern,
          apiPath: apiPath,
        );
        if (mapped != null) {
          return mapped;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<http.Response> _get(Uri url) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': userAgent,
    };
    final client = httpClient;
    if (client != null) {
      return client.get(url, headers: headers).timeout(timeout);
    }
    final owned = http.Client();
    return owned
        .get(url, headers: headers)
        .timeout(timeout)
        .whenComplete(owned.close);
  }
}

Uri? _parseSolanaAction(String input) {
  const prefix = 'solana-action:';
  if (!input.startsWith(prefix)) {
    return null;
  }
  var rest = input.substring(prefix.length);
  if (!rest.contains('://') && rest.contains('%')) {
    try {
      rest = Uri.decodeFull(rest);
    } on ArgumentError {
      return null;
    }
  }
  final action = Uri.tryParse(rest);
  if (action == null || !_isHttp(action) || !action.hasAuthority) {
    return null;
  }
  return action;
}

bool _isHttp(Uri uri) => uri.scheme == 'https' || uri.scheme == 'http';

String _matchSubject(Uri websiteUrl, String pathPattern) {
  if (pathPattern.startsWith('https://') || pathPattern.startsWith('http://')) {
    return _origin(websiteUrl).toString();
  }
  if (websiteUrl.path.isEmpty) {
    return '/';
  }
  return websiteUrl.path;
}

/// Origin and path of [uri], without a query or fragment.
///
/// [Uri.replace] cannot drop both pieces without leaving a trailing `?` or
/// `#`, which would break exact `actions.json` rules.
Uri _origin(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}

RegExp _compilePattern(String pattern) {
  final buffer = StringBuffer('^');
  var index = 0;
  while (index < pattern.length) {
    if (pattern.startsWith('**', index)) {
      buffer.write('(.*)');
      index += 2;
      continue;
    }
    if (pattern[index] == '*') {
      buffer.write('([^/]+)');
      index += 1;
      continue;
    }
    final character = pattern[index];
    if (r'\.^$|+?()[]{}'.contains(character)) {
      buffer.write('\\$character');
    } else {
      buffer.write(character);
    }
    index += 1;
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

Uri _copyQuery(Uri mapped, Uri original) {
  if (!original.hasQuery) {
    return mapped;
  }
  final merged = <String, String>{
    ...mapped.queryParameters,
    ...original.queryParameters,
  };
  return mapped.replace(queryParameters: merged);
}
