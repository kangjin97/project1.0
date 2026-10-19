import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/features/auth/welcome_page.dart';

final _rules = RegExp(r'^[a-z0-9_]{3,30}$');

void main() {
  test('a name becomes a username', () {
    expect(usernameBase('Kang Jin', 'k@x.com'), 'kang_jin');
    expect(usernameBase('  Zoë O’Brien-Smith ', null), 'zo_o_brien_smith');
  });

  test('no usable name: the email’s first part, then a fallback', () {
    expect(usernameBase(null, 'kangjin.97@gmail.com'), 'kangjin_97');
    expect(usernameBase('李', 'ab@x.com'), 'user_ab');
    expect(usernameBase(null, null), 'user');
  });

  test('suggestions always follow the sign-up rules', () {
    for (final name in ['A', 'Kang Jin', 'x' * 60, '__', 'Mary-Jane Watson Parker the Third of Queens']) {
      final base = usernameBase(name, 'someone@x.com');
      for (final c in usernameCandidates(base, random: Random(1))) {
        expect(_rules.hasMatch(c), isTrue, reason: '"$c" from "$name"');
      }
    }
  });

  test('a taken name gets numbers', () {
    final c = usernameCandidates('kang_jin', random: Random(1));
    expect(c.take(3), ['kang_jin', 'kang_jin2', 'kang_jin3']);
    expect(c.last, matches(RegExp(r'^kang_jin\d{4}$')));
  });
}
