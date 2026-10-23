import 'package:flutter_test/flutter_test.dart';
import 'package:solana_blinks/solana_blinks.dart';

void main() {
  test('reports the published package version', () {
    expect(solanaBlinksVersion, '0.1.0');
  });
}
