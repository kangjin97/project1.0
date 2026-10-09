import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/app_clock.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('aliases such as Asia/Kuala_Lumpur resolve', () {
    AppClock.use('Asia/Kuala_Lumpur');
    expect(AppClock.zoneName, 'Asia/Kuala_Lumpur');
    expect(AppClock.offsetLabel(), 'UTC+08:00');
  });

  test('server instants are shown as wall-clock time in the chosen zone', () {
    final instant = DateTime.utc(2026, 10, 10, 10); // 10:00 UTC
    AppClock.use('Asia/Singapore');
    expect(AppClock.inZone(instant).hour, 18);
    AppClock.use('Europe/London'); // BST in October
    expect(AppClock.inZone(instant).hour, 11);
    AppClock.use('America/Los_Angeles');
    final la = AppClock.inZone(instant);
    expect((la.day, la.hour), (10, 3));
  });

  test('picked times are interpreted in the chosen zone', () {
    AppClock.use('Asia/Kolkata');
    final picked = AppClock.at(2026, 10, 10, 18, 30);
    expect(picked.toUtc(), DateTime.utc(2026, 10, 10, 13, 0));
  });

  test('offset labels', () {
    expect(formatOffset(0), 'UTC±00:00');
    expect(formatOffset(345), 'UTC+05:45');
    expect(formatOffset(-180), 'UTC−03:00');
  });
}
