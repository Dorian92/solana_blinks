import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  group('validateActionParameter', () {
    test('requires a value and checks number bounds', () {
      const amount = ActionParameter(
        name: 'amount',
        label: 'Amount',
        required: true,
        type: ActionParameterType.number,
        min: 1,
        max: 5,
      );

      expect(validateActionParameter(amount, '  '), 'Amount is required.');
      expect(validateActionParameter(amount, '0'), 'Must be at least 1.');
      expect(validateActionParameter(amount, '9'), 'Must be at most 5.');
      expect(validateActionParameter(amount, 'nope'), 'Enter a number.');
      expect(validateActionParameter(amount, '2'), isNull);
    });

    test('checks email, url, pattern, and ignores a broken pattern', () {
      const email = ActionParameter(
        name: 'email',
        type: ActionParameterType.email,
      );
      const site = ActionParameter(name: 'site', type: ActionParameterType.url);
      const code = ActionParameter(
        name: 'code',
        pattern: r'^[A-Z]+$',
        patternDescription: 'Use capital letters.',
      );
      const broken = ActionParameter(name: 'note', pattern: '[');

      expect(validateActionParameter(email, 'ada'), 'Enter a valid email.');
      expect(validateActionParameter(email, 'ada@example.com'), isNull);
      expect(
        validateActionParameter(site, 'example.com'),
        'Enter a valid URL.',
      );
      expect(validateActionParameter(site, 'https://example.com'), isNull);
      expect(validateActionParameter(code, 'ab'), 'Use capital letters.');
      expect(validateActionParameter(broken, 'anything'), isNull);
    });

    test('optional empty input skips later checks', () {
      const note = ActionParameter(
        name: 'note',
        type: ActionParameterType.textarea,
        min: 4,
      );

      expect(validateActionParameter(note, ''), isNull);
      expect(
        validateActionParameter(note, 'hey'),
        'Must be at least 4 characters.',
      );
    });
  });
}
