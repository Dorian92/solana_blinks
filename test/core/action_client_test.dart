import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana_blinks/solana_blinks.dart';

class _HangClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  const actionUrl = 'https://alice.com/api/tip';

  group('ActionClient.fetchAction and postAction', () {
    test('GETs an action and POSTs the account', () async {
      final requests = <http.Request>[];
      final client = ActionClient(
        userAgent: 'solana_blinks-test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(const <String, Object?>{
                'title': 'Tip',
                'icon': 'https://alice.com/icon.png',
                'description': 'Send a devnet tip.',
                'label': 'Send tip',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(const <String, Object?>{
              'transaction': 'AQID',
              'message': 'Thanks',
            }),
            200,
          );
        }),
      );

      final action = await client.fetchAction(Uri.parse(actionUrl));
      expect(action.title, 'Tip');
      expect(action.actions.single.href, actionUrl);

      final posted = await client.postAction(
        Uri.parse(actionUrl),
        '11111111111111111111111111111111',
      );
      expect(posted.transaction, 'AQID');
      expect(posted.message, 'Thanks');

      expect(requests, hasLength(2));
      expect(requests[0].method, 'GET');
      expect(requests[0].headers['accept'], 'application/json');
      expect(requests[0].headers['user-agent'], 'solana_blinks-test');
      expect(requests[1].method, 'POST');
      expect(jsonDecode(requests[1].body), <String, Object?>{
        'account': '11111111111111111111111111111111',
      });
      expect(
        requests[1].headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('maps an error JSON message into BlinkException', () async {
      final client = ActionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(const <String, Object?>{
              'message': 'Insufficient funds',
            }),
            400,
          );
        }),
      );

      expect(
        () => client.postAction(Uri.parse(actionUrl), 'pubkey'),
        throwsA(
          isA<BlinkException>()
              .having((error) => error.message, 'message', 'Insufficient funds')
              .having((error) => error.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('wraps a timeout in BlinkException', () async {
      final client = ActionClient(
        timeout: const Duration(milliseconds: 10),
        httpClient: _HangClient(),
      );

      expect(
        () => client.fetchAction(Uri.parse(actionUrl)),
        throwsA(
          isA<BlinkException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });

  group('ActionClient.resolveHref', () {
    test('substitutes templates and resolves relative hrefs on the origin', () {
      final client = ActionClient();
      final base = Uri.parse('https://alice.com/actions/tip');

      expect(
        client.resolveHref('/api/donate/{amount}', const {
          'amount': '1.5 SOL',
        }, base),
        Uri.parse('https://alice.com/api/donate/1.5%20SOL'),
      );
      expect(
        client.resolveHref('stake?amount={amount}', const {
          'amount': '2',
        }, base),
        Uri.parse('https://alice.com/stake?amount=2'),
      );
      expect(
        client.resolveHref('https://actions.alice.com/fixed', const {}, base),
        Uri.parse('https://actions.alice.com/fixed'),
      );
    });

    test('rejects a placeholder with no value', () {
      final client = ActionClient();

      expect(
        () =>
            client.resolveHref('/api/{amount}', const {}, Uri.parse(actionUrl)),
        throwsA(
          isA<BlinkException>().having(
            (error) => error.message,
            'message',
            contains('{amount}'),
          ),
        ),
      );
    });
  });

  group('ActionClient.followNext', () {
    test('returns an inline next action without a request', () async {
      final client = ActionClient(
        httpClient: MockClient((request) async {
          fail('inline chaining must not call the network');
        }),
      );
      const inline = ActionGetResponse(
        icon: 'https://alice.com/done.png',
        title: 'Done',
        description: 'Sent',
        label: 'Close',
        type: ActionType.completed,
        actions: <LinkedAction>[],
      );

      final next = await client.followNext(
        const ActionPostResponse(
          transaction: 'AQID',
          next: InlineNextActionLink(action: inline),
        ),
        'signature',
      );

      expect(next.title, 'Done');
      expect(next.type, ActionType.completed);
    });

    test('POSTs account and signature to a same-origin callback', () async {
      final requests = <http.Request>[];
      final client = ActionClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/tip') {
            return http.Response(
              jsonEncode(const <String, Object?>{
                'transaction': 'AQID',
                'links': <String, Object?>{
                  'next': <String, Object?>{
                    'type': 'post',
                    'href': '/api/tip/next',
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(const <String, Object?>{
              'type': 'completed',
              'icon': 'https://alice.com/done.png',
              'title': 'Tipped',
              'description': 'The transfer confirmed.',
              'label': 'Done',
            }),
            200,
          );
        }),
      );

      final posted = await client.postAction(Uri.parse(actionUrl), 'Pubkey111');
      final next = await client.followNext(posted, 'sig123');

      expect(next.type, ActionType.completed);
      expect(next.title, 'Tipped');
      expect(requests, hasLength(2));
      expect(requests[1].url, Uri.parse('https://alice.com/api/tip/next'));
      expect(jsonDecode(requests[1].body), <String, Object?>{
        'account': 'Pubkey111',
        'signature': 'sig123',
      });
    });

    test('refuses a next link on another origin', () async {
      final client = ActionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(const <String, Object?>{'transaction': 'AQID'}),
            200,
          );
        }),
      );
      await client.postAction(Uri.parse(actionUrl), 'Pubkey111');

      expect(
        () => client.followNext(
          const ActionPostResponse(
            transaction: 'AQID',
            next: PostNextActionLink(href: 'https://evil.example/steal'),
          ),
          'sig123',
        ),
        throwsA(
          isA<BlinkException>().having(
            (error) => error.message,
            'message',
            contains('evil.example'),
          ),
        ),
      );
    });
  });
}
