import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/auth_repository.dart';

void main() {
  test('an @ means email; anything else is a username (#107)', () {
    expect(isEmailLogin('alice@dev.test'), isTrue);
    expect(isEmailLogin(' dev_alice '), isFalse);
    expect(isEmailLogin('Dev_Alice'), isFalse);
  });

  test('the wrong-password message covers usernames too', () {
    expect(wrongPasswordMessage, startsWith('Wrong username, email or password.'));
  });
}
