import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana_blinks/solana_blinks.dart';

import '../helpers/fake_wallet_adapter.dart';

final _base = Uri.parse('https://alice.com/api/tip');

const _tip = ActionGetResponse(
  icon: '',
  title: 'Tip Alice',
  description: 'Send a devnet tip.',
  label: 'Send tip',
  actions: <LinkedAction>[
    LinkedAction(href: 'https://alice.com/api/tip', label: 'Send tip'),
    LinkedAction(
      href: 'https://alice.com/api/tip?kind=thanks',
      label: 'Thanks',
    ),
  ],
);

void main() {
  group('BlinkCard', () {
    testWidgets('renders title, description, host, and action buttons', (
      tester,
    ) async {
      await _pump(
        tester,
        BlinkCard(
          action: _tip,
          baseUrl: _base,
          adapter: FakeWalletAdapter(),
          client: _client(),
          executor: _executor(FakeWalletAdapter()),
        ),
      );

      expect(find.text('Tip Alice'), findsOneWidget);
      expect(find.text('Send a devnet tip.'), findsOneWidget);
      expect(find.byKey(const Key('blink-host')), findsOneWidget);
      expect(find.text('alice.com'), findsOneWidget);
      expect(find.byKey(const Key('blink-action-Send tip')), findsOneWidget);
      expect(find.byKey(const Key('blink-action-Thanks')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('blocks a required parameter and then submits it', (
      tester,
    ) async {
      final requests = <Uri>[];
      final wallet = FakeWalletAdapter(
        supportsSignAndSend: true,
        signAndSendSignatures: const <String>['walletSignature'],
      );
      await _pump(
        tester,
        BlinkCard(
          action: const ActionGetResponse(
            icon: '',
            title: 'Tip Alice',
            description: 'Send a devnet tip.',
            label: 'Send',
            actions: <LinkedAction>[
              LinkedAction(
                href: 'https://alice.com/api/tip?amount={amount}',
                label: 'Send',
                parameters: <ActionParameter>[
                  ActionParameter(
                    name: 'amount',
                    label: 'Amount',
                    required: true,
                    type: ActionParameterType.number,
                    min: 1,
                    max: 5,
                  ),
                ],
              ),
            ],
          ),
          baseUrl: _base,
          adapter: wallet,
          client: _client(onRequest: (request) => requests.add(request.url)),
          executor: _executor(wallet),
        ),
      );

      await tester.tap(find.byKey(const Key('blink-action-Send')));
      await tester.pump();
      expect(find.text('Amount is required.'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.enterText(find.byKey(const Key('blink-param-amount')), '0');
      await tester.tap(find.byKey(const Key('blink-action-Send')));
      await tester.pump();
      expect(find.text('Must be at least 1.'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.enterText(find.byKey(const Key('blink-param-amount')), '2');
      await tester.tap(find.byKey(const Key('blink-action-Send')));
      await tester.pump();
      expect(find.byKey(const Key('blink-signature')), findsOneWidget);
      expect(find.text('walletSignature'), findsOneWidget);
      expect(find.text('Tip sent'), findsOneWidget);
      expect(requests.single.queryParameters['amount'], '2');
      expect(wallet.isConnected, isTrue);
    });

    testWidgets('shows a disabled action as a disabled button', (tester) async {
      await _pump(
        tester,
        BlinkCard(
          action: const ActionGetResponse(
            icon: '',
            title: 'Paused',
            description: 'Not taking tips.',
            label: 'Send',
            disabled: true,
            actions: <LinkedAction>[
              LinkedAction(href: 'https://alice.com/api/tip', label: 'Send'),
            ],
          ),
          baseUrl: _base,
          adapter: FakeWalletAdapter(),
          client: _client(),
          executor: _executor(FakeWalletAdapter()),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('blink-action-Send')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows the action error message', (tester) async {
      await _pump(
        tester,
        BlinkCard(
          action: const ActionGetResponse(
            icon: '',
            title: 'Tip Alice',
            description: 'Send a devnet tip.',
            label: 'Send',
            error: ActionError(message: 'Maintenance'),
            actions: <LinkedAction>[
              LinkedAction(href: 'https://alice.com/api/tip', label: 'Send'),
            ],
          ),
          baseUrl: _base,
          adapter: FakeWalletAdapter(),
          client: _client(),
          executor: _executor(FakeWalletAdapter()),
        ),
      );

      expect(find.byKey(const Key('blink-error')), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
    });

    testWidgets('replaces the card with an inline completed action', (
      tester,
    ) async {
      final wallet = FakeWalletAdapter(
        supportsSignAndSend: true,
        signAndSendSignatures: const <String>['chainedSignature'],
      );
      String? reported;
      await _pump(
        tester,
        BlinkCard(
          action: _tip,
          baseUrl: _base,
          adapter: wallet,
          client: _client(
            postBody: <String, Object?>{
              'transaction': 'AQID',
              'message': 'Tip sent',
              'links': <String, Object?>{
                'next': <String, Object?>{
                  'type': 'inline',
                  'action': <String, Object?>{
                    'type': 'completed',
                    'icon': '',
                    'title': 'All done',
                    'description': 'Thanks for the tip',
                    'label': 'Done',
                  },
                },
              },
            },
          ),
          executor: _executor(wallet),
          onSuccess: (signature) => reported = signature,
        ),
      );

      await tester.tap(find.byKey(const Key('blink-action-Send tip')));
      await tester.pump();

      expect(find.text('All done'), findsOneWidget);
      expect(find.text('Thanks for the tip'), findsOneWidget);
      expect(find.text('chainedSignature'), findsOneWidget);
      expect(find.byKey(const Key('blink-action-Send tip')), findsNothing);
      expect(reported, 'chainedSignature');
    });

    testWidgets('uses the wallet and client from BlinkScope', (tester) async {
      final wallet = FakeWalletAdapter(
        supportsSignAndSend: true,
        signAndSendSignatures: const <String>['walletSignature'],
      );
      final accounts = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlinkScope(
              wallet: wallet,
              client: _client(
                onRequest: (request) {
                  final body = jsonDecode(request.body) as Map<String, Object?>;
                  accounts.add(body['account']! as String);
                },
              ),
              executor: _executor(wallet),
              child: BlinkCard(action: _tip, baseUrl: _base),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('blink-action-Thanks')));
      await tester.pump();
      expect(accounts, <String>[wallet.address]);
      expect(find.text('walletSignature'), findsOneWidget);
    });

    testWidgets('loads a solana-action URL', (tester) async {
      await _pump(
        tester,
        BlinkCard(
          url: 'solana-action:https://alice.com/api/tip',
          adapter: FakeWalletAdapter(),
          client: _client(
            getBody: const <String, Object?>{
              'title': 'Fetched tip',
              'icon': '',
              'description': 'From the server.',
              'label': 'Send',
            },
          ),
          executor: _executor(FakeWalletAdapter()),
        ),
      );
      await tester.pump();

      expect(find.text('Fetched tip'), findsOneWidget);
      expect(find.text('alice.com'), findsOneWidget);
      expect(find.byKey(const Key('blink-action-Send')), findsOneWidget);
    });

    testWidgets('renders select, radio, and checkbox parameters', (
      tester,
    ) async {
      await _pump(
        tester,
        BlinkCard(
          action: const ActionGetResponse(
            icon: '',
            title: 'Vote',
            description: 'Pick one.',
            label: 'Vote',
            actions: <LinkedAction>[
              LinkedAction(
                href: 'https://alice.com/api/vote?choice={choice}&tags={tags}',
                label: 'Vote',
                parameters: <ActionParameter>[
                  ActionParameter(
                    name: 'choice',
                    label: 'Choice',
                    type: ActionParameterType.select,
                    options: <ActionParameterOption>[
                      ActionParameterOption(label: 'Yes', value: 'yes'),
                      ActionParameterOption(
                        label: 'No',
                        value: 'no',
                        selected: true,
                      ),
                    ],
                  ),
                  ActionParameter(
                    name: 'side',
                    label: 'Side',
                    type: ActionParameterType.radio,
                    options: <ActionParameterOption>[
                      ActionParameterOption(label: 'Left', value: 'left'),
                      ActionParameterOption(label: 'Right', value: 'right'),
                    ],
                  ),
                  ActionParameter(
                    name: 'tags',
                    label: 'Tags',
                    type: ActionParameterType.checkbox,
                    options: <ActionParameterOption>[
                      ActionParameterOption(
                        label: 'Fun',
                        value: 'fun',
                        selected: true,
                      ),
                      ActionParameterOption(label: 'Fast', value: 'fast'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          baseUrl: _base,
          adapter: FakeWalletAdapter(),
          client: _client(),
          executor: _executor(FakeWalletAdapter()),
        ),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      final fun = tester.widget<CheckboxListTile>(
        find.byKey(const Key('blink-param-tags-fun')),
      );
      expect(fun.value, isTrue);
    });

    testWidgets('reports an external link instead of posting', (tester) async {
      final requests = <http.Request>[];
      Uri? opened;
      await _pump(
        tester,
        BlinkCard(
          action: const ActionGetResponse(
            icon: '',
            title: 'Docs',
            description: 'Read more.',
            label: 'Open',
            actions: <LinkedAction>[
              LinkedAction(
                href: 'https://alice.com/docs',
                label: 'Open',
                type: ActionType.externalLink,
              ),
            ],
          ),
          baseUrl: _base,
          adapter: FakeWalletAdapter(),
          client: _client(onRequest: requests.add),
          executor: _executor(FakeWalletAdapter()),
          onExternalLink: (uri) => opened = uri,
        ),
      );

      await tester.tap(find.byKey(const Key('blink-action-Open')));
      await tester.pump();
      expect(opened, Uri.parse('https://alice.com/docs'));
      expect(requests, isEmpty);
    });

    testWidgets('asks for a wallet when nothing was injected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlinkCard(action: _tip, baseUrl: _base),
          ),
        ),
      );

      expect(find.textContaining('BlinkScope'), findsOneWidget);
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

ActionClient _client({
  Map<String, Object?>? postBody,
  Map<String, Object?>? getBody,
  void Function(http.Request request)? onRequest,
}) {
  return ActionClient(
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(
            getBody ??
                const <String, Object?>{
                  'title': 'Fetched tip',
                  'icon': '',
                  'description': 'From the server.',
                  'label': 'Send',
                },
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode(
          postBody ??
              const <String, Object?>{
                'transaction': 'AQID',
                'message': 'Tip sent',
              },
        ),
        200,
      );
    }),
  );
}

TransactionExecutor _executor(FakeWalletAdapter wallet) {
  return TransactionExecutor(
    wallet: wallet,
    rpcUrl: 'https://rpc.test',
    pollInterval: Duration.zero,
    confirmationTimeout: const Duration(seconds: 1),
    httpClient: MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': payload['id'],
          'result': <String, Object?>{
            'context': <String, Object?>{'slot': 1},
            'value': <Object?>[
              <String, Object?>{'confirmationStatus': 'confirmed', 'err': null},
            ],
          },
        }),
        200,
      );
    }),
  );
}
