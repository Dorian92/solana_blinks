import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  group('ActionGetResponse', () {
    test('builds a default action when links.actions is missing', () {
      final action = ActionGetResponse.fromJson(const <String, Object?>{
        'title': 'HackerHouse Events',
        'icon': 'https://example.com/icon.png',
        'description': 'Claim your Hackerhouse access token.',
        'label': 'Claim Access Token',
        'unknown': true,
      }, actionUrl: 'https://example.com/claim');

      expect(action.type, ActionType.action);
      expect(action.disabled, isFalse);
      expect(action.error, isNull);
      expect(action.actions, hasLength(1));
      expect(action.actions.single.label, 'Claim Access Token');
      expect(action.actions.single.href, 'https://example.com/claim');
      expect(action.actions.single.parameters, isEmpty);
    });

    test('parses linked actions and leaves the root label off the buttons', () {
      final action = ActionGetResponse.fromJson(const <String, Object?>{
        'title': 'Realms DAO Platform',
        'icon': 'https://example.com/icon.png',
        'description': 'Vote on DAO governance proposals #1234.',
        'label': 'Vote',
        'links': <String, Object?>{
          'actions': <Object?>[
            <String, Object?>{
              'label': 'Vote Yes',
              'href': '/api/proposal/1234/vote?choice=yes',
            },
            <String, Object?>{
              'label': 'Vote No',
              'href': '/api/proposal/1234/vote?choice=no',
            },
            <String, Object?>{
              'label': 'Abstain from Vote',
              'href': '/api/proposal/1234/vote?choice=abstain',
            },
          ],
        },
      });

      expect(action.label, 'Vote');
      expect(action.actions.map((linked) => linked.label), [
        'Vote Yes',
        'Vote No',
        'Abstain from Vote',
      ]);
      expect(action.actions.first.href, '/api/proposal/1234/vote?choice=yes');
    });

    test('parses parameters, including select options and bounds', () {
      final action = ActionGetResponse.fromJson(const <String, Object?>{
        'icon': 'https://example.com/icon.png',
        'label': 'Donate SOL',
        'title': 'Donate to GoodCause Charity',
        'description': 'Help support this charity by donating SOL.',
        'disabled': true,
        'error': <String, Object?>{'message': 'Donation window is closing.'},
        'links': <String, Object?>{
          'actions': <Object?>[
            <String, Object?>{
              'type': 'transaction',
              'label': 'Donate',
              'href': '/api/donate/{amount}',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'amount',
                  'label': 'SOL amount',
                  'required': true,
                  'type': 'number',
                  'pattern': r'^\d+(\.\d+)?$',
                  'patternDescription': 'Enter a SOL amount.',
                  'min': 0.01,
                  'max': 5,
                },
                <String, Object?>{
                  'name': 'cause',
                  'type': 'select',
                  'options': <Object?>[
                    <String, Object?>{
                      'label': 'Food',
                      'value': 'food',
                      'selected': true,
                    },
                    <String, Object?>{'label': 'Shelter', 'value': 'shelter'},
                  ],
                },
                <String, Object?>{
                  'name': 'when',
                  'type': 'date',
                  'min': '2026-01-01',
                  'max': '2026-12-31',
                },
                <String, Object?>{'name': '', 'label': 'ignored'},
                'not-a-parameter',
              ],
            },
          ],
        },
      });

      expect(action.disabled, isTrue);
      expect(action.error?.message, 'Donation window is closing.');
      final donate = action.actions.single;
      expect(donate.type, ActionType.transaction);
      expect(donate.parameters, hasLength(3));

      final amount = donate.parameters[0];
      expect(amount.name, 'amount');
      expect(amount.required, isTrue);
      expect(amount.type, ActionParameterType.number);
      expect(amount.min, 0.01);
      expect(amount.max, 5);
      expect(amount.patternDescription, 'Enter a SOL amount.');

      final cause = donate.parameters[1];
      expect(cause.type, ActionParameterType.select);
      expect(cause.type.isSelectable, isTrue);
      expect(
        cause.options.singleWhere((option) => option.selected).value,
        'food',
      );

      expect(donate.parameters[2].type, ActionParameterType.date);
      expect(donate.parameters[2].min, '2026-01-01');
    });

    test('defaults an unknown parameter type to text', () {
      final parameter = ActionParameter.fromJson(const <String, Object?>{
        'name': 'note',
        'type': 'file',
      });

      expect(parameter?.type, ActionParameterType.text);
    });

    test('round-trips a completed action', () {
      const original = ActionGetResponse(
        type: ActionType.completed,
        icon: 'https://example.com/done.png',
        title: 'Sent',
        description: 'The tip was delivered.',
        label: 'Done',
        actions: <LinkedAction>[],
      );

      final restored = ActionGetResponse.fromJson(original.toJson());

      expect(restored.type, ActionType.completed);
      expect(restored.title, 'Sent');
      expect(restored.actions, isEmpty);
    });
  });

  group('ActionPostResponse', () {
    test('parses a transaction, message, and post next link', () {
      final response = ActionPostResponse.fromJson(const <String, Object?>{
        'type': 'transaction',
        'transaction': 'AQID',
        'message': 'Thanks for the tip',
        'ignored': 1,
        'links': <String, Object?>{
          'next': <String, Object?>{
            'type': 'post',
            'href': '/api/actions/next',
          },
        },
      });

      expect(response.transaction, 'AQID');
      expect(response.message, 'Thanks for the tip');
      expect(response.type, ActionType.transaction);
      final next = response.next;
      expect(next, isA<PostNextActionLink>());
      expect((next! as PostNextActionLink).href, '/api/actions/next');
    });

    test('parses an inline next action', () {
      final response = ActionPostResponse.fromJson(const <String, Object?>{
        'transaction': 'AQID',
        'links': <String, Object?>{
          'next': <String, Object?>{
            'type': 'inline',
            'action': <String, Object?>{
              'type': 'completed',
              'icon': 'https://example.com/icon.png',
              'title': 'Done',
              'description': 'Sent',
              'label': 'Close',
            },
          },
        },
      });

      final next = response.next;
      expect(next, isA<InlineNextActionLink>());
      final action = (next! as InlineNextActionLink).action;
      expect(action.type, ActionType.completed);
      expect(action.title, 'Done');
      expect(action.actions.single.href, '');
    });

    test('drops an unusable next link', () {
      final response = ActionPostResponse.fromJson(const <String, Object?>{
        'transaction': 'AQID',
        'links': <String, Object?>{
          'next': <String, Object?>{'type': 'post'},
        },
      });

      expect(response.next, isNull);
    });

    test('round-trips the request body used for chaining', () {
      final request = ActionPostRequest(
        account: '11111111111111111111111111111111',
        signature: '5' * 64,
      );

      expect(request.toJson(), <String, Object?>{
        'account': '11111111111111111111111111111111',
        'signature': '5' * 64,
      });
      expect(
        ActionPostRequest.fromJson(request.toJson()).account,
        request.account,
      );
    });

    test('parses an external-link response', () {
      final response = ActionPostResponse.fromJson(const <String, Object?>{
        'type': 'external-link',
        'externalLink': 'https://example.com/more',
        'message': 'Continue on the site',
      });

      expect(response.type, ActionType.externalLink);
      expect(response.externalLink, 'https://example.com/more');
      expect(response.transaction, isNull);
    });
  });
}
