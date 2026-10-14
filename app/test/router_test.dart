import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/router.dart';

void main() {
  test('email change: the note asking to confirm the other address is shown', () {
    final uri = Uri.parse('https://easyplan-hehe.netlify.app/?message=Confirmation+link+accepted.+Please+proceed+to+confirm+link+sent+to+the+other+email');
    expect(authLinkNotice(uri), 'Confirmation link accepted. Please proceed to confirm link sent to the other email');
  });

  test('expired links show their error', () {
    final uri = Uri.parse('/?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired');
    expect(authLinkNotice(uri), 'Email link is invalid or has expired');
  });

  test('sign-up confirmation codes carry no note', () {
    expect(authLinkNotice(Uri.parse('/?code=abc123')), isNull);
    expect(authLinkNotice(Uri.parse('/')), isNull);
  });
}
