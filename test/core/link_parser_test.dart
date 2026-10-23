import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  group('BlinkLinkParser solana-action and action query', () {
    late BlinkLinkParser parser;

    setUp(() {
      parser = BlinkLinkParser(
        httpClient: MockClient((request) async {
          fail('network should not be used for explicit action URLs');
        }),
      );
    });

    test('unwraps a solana-action URL', () async {
      final resolved = await parser.parse(
        'solana-action:https://actions.alice.com/donate',
      );

      expect(resolved, Uri.parse('https://actions.alice.com/donate'));
    });

    test('unwraps a percent-encoded solana-action URL', () async {
      final resolved = await parser.parse(
        'solana-action:https%3A%2F%2Factions.alice.com%2Fdonate%3Famount%3D1',
      );

      expect(resolved, Uri.parse('https://actions.alice.com/donate?amount=1'));
    });

    test('resolves a dial.to style action query parameter', () async {
      final resolved = await parser.parse(
        'https://dial.to/?action=solana-action%3Ahttps%3A%2F%2Factions.alice.com%2Fdonate',
      );

      expect(resolved, Uri.parse('https://actions.alice.com/donate'));
    });

    test(
      'accepts an action query parameter that is already an https URL',
      () async {
        final resolved = await parser.parse(
          'https://example.domain/?action=https%3A%2F%2Factions.alice.com%2Fdonate',
        );

        expect(resolved, Uri.parse('https://actions.alice.com/donate'));
      },
    );

    test('rejects a solana-action value that is not an http URL', () async {
      expect(await parser.parse('solana-action:not-a-url'), isNull);
      expect(await parser.parse(''), isNull);
      expect(await parser.parse('notaurl'), isNull);
    });
  });

  group('BlinkLinkParser actions.json', () {
    test('maps wildcard rules and keeps the original query', () async {
      final parser = BlinkLinkParser(
        httpClient: MockClient((request) async {
          expect(request.url, Uri.parse('https://alice.com/actions.json'));
          expect(request.headers['accept'], 'application/json');
          expect(request.headers['user-agent'], blinkLinkParserUserAgent);
          return http.Response(
            jsonEncode(<String, Object?>{
              'rules': <Object?>[
                <String, Object?>{'pathPattern': '/buy', 'apiPath': '/api/buy'},
                <String, Object?>{
                  'pathPattern': '/actions/*',
                  'apiPath': '/api/actions/*',
                },
                <String, Object?>{
                  'pathPattern': '/donate/*',
                  'apiPath': 'https://api.dialect.com/api/v1/donate/*',
                },
                <String, Object?>{
                  'pathPattern': '/api/actions/**',
                  'apiPath': '/api/actions/**',
                },
                <String, Object?>{
                  'pathPattern': '/category/*/item/**',
                  'apiPath': '/api/category/*/item/**',
                },
              ],
            }),
            200,
          );
        }),
      );

      expect(
        await parser.parse('https://alice.com/buy'),
        Uri.parse('https://alice.com/api/buy'),
      );
      expect(
        await parser.parse('https://alice.com/actions/donate'),
        Uri.parse('https://alice.com/api/actions/donate'),
      );
      expect(
        await parser.parse('https://alice.com/donate/abc?ref=tw'),
        Uri.parse('https://api.dialect.com/api/v1/donate/abc?ref=tw'),
      );
      expect(
        await parser.parse('https://alice.com/api/actions/tip/now'),
        Uri.parse('https://alice.com/api/actions/tip/now'),
      );
      expect(
        await parser.parse('https://alice.com/category/abc/item/def/ghi'),
        Uri.parse('https://alice.com/api/category/abc/item/def/ghi'),
      );
    });

    test('does not let a single star cross a path segment', () {
      final mapped = BlinkLinkParser.mapRule(
        websiteUrl: Uri.parse('https://alice.com/trade/123/confirm'),
        pathPattern: '/trade/*',
        apiPath: '/api/trade/*',
      );

      expect(mapped, isNull);
    });

    test('matches an absolute pathPattern', () {
      final mapped = BlinkLinkParser.mapRule(
        websiteUrl: Uri.parse('https://alice.com/exact-path'),
        pathPattern: 'https://alice.com/exact-path',
        apiPath: '/api/exact-path',
      );

      expect(mapped, Uri.parse('https://alice.com/api/exact-path'));
    });

    test('returns null when no rule matches', () async {
      final parser = BlinkLinkParser(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'rules': <Object?>[
                <String, Object?>{
                  'pathPattern': '/donate/*',
                  'apiPath': '/api/donate/*',
                },
              ],
            }),
            200,
          );
        }),
      );

      expect(await parser.parse('https://alice.com/other'), isNull);
    });

    test('returns null when actions.json fails', () async {
      final parser = BlinkLinkParser(
        httpClient: MockClient((request) async {
          return http.Response('missing', 404);
        }),
      );

      expect(await parser.parse('https://alice.com/donate'), isNull);
    });

    test('returns null when actions.json is not JSON', () async {
      final parser = BlinkLinkParser(
        httpClient: MockClient((request) async {
          return http.Response('not-json', 200);
        }),
      );

      expect(await parser.parse('https://alice.com/donate'), isNull);
    });
  });
}
