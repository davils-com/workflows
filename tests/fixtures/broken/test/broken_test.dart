import 'package:davils_ci_broken/davils_ci_broken.dart';
import 'package:test/test.dart';

void main() {
  test('fails on purpose', () => expect(answer(), 41));
}
