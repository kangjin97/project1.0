import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/widgets/password_field.dart';

void main() {
  testWidgets('the eye button shows and hides the password (#109)', (tester) async {
    final controller = TextEditingController(text: 'secret-123');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PasswordField(controller: controller, label: 'Password')),
    ));
    bool hidden() => tester.widget<EditableText>(find.byType(EditableText)).obscureText;

    expect(hidden(), isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(hidden(), isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(hidden(), isTrue);
  });

  testWidgets('a confirm field refuses a different password', (tester) async {
    final form = GlobalKey<FormState>();
    final password = TextEditingController(text: 'secret-123');
    final confirm = TextEditingController(text: 'secret-124');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: form,
          child: Column(children: [
            PasswordField(controller: password, label: 'Password'),
            PasswordField(
              controller: confirm,
              label: 'Confirm password',
              validator: (v) => v == password.text ? null : 'Passwords don’t match',
            ),
          ]),
        ),
      ),
    ));
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Passwords don’t match'), findsOneWidget);

    confirm.text = 'secret-123';
    expect(form.currentState!.validate(), isTrue);
  });
}
