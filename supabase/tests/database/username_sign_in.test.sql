-- Sign in with a username: the email lookup and the guessing limit (#107).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann_test_107"}');

-- Clients can't use any of it.
set local role authenticated;
select throws_ok($$ select email_for_username('ann_test_107') $$, '42501', null, 'signed-in users can''t look up emails');
select throws_ok($$ select * from username_sign_in_failures $$, '42501', null, 'or read the attempts');
set local role anon;
select throws_ok($$ select email_for_username('ann_test_107') $$, '42501', null, 'nor can signed-out callers');
select throws_ok($$ select record_username_sign_in_failure('ann_test_107') $$, '42501', null, 'or record attempts');

-- The Edge Function's role.
set local role service_role;
select is(email_for_username('ann_test_107'), 'ann@example.test', 'the service role finds the email');
select is(email_for_username('  ANN_Test_107 '), 'ann@example.test', 'ignoring letter case and spaces');
select is(email_for_username('nobody_test_107'), null, 'an unknown username gives no email');

-- Nine failures still allow a try; the tenth locks it for 15 minutes.
select record_username_sign_in_failure('ann_test_107') from generate_series(1, 9);
select lives_ok($$ select email_for_username('ann_test_107') $$, '9 failures: still allowed');
select record_username_sign_in_failure('ANN_TEST_107');
select throws_ok($$ select email_for_username('ann_test_107') $$, 'PT429', null, '10 failures in 15 minutes: paused');

-- Older failures don't count.
reset role;
update username_sign_in_failures set attempted_at = now() - interval '16 minutes' where username = 'ann_test_107';
set local role service_role;
select lives_ok($$ select email_for_username('ann_test_107') $$, 'failures older than 15 minutes don''t count');

-- A success clears the count.
select record_username_sign_in_failure('ann_test_107') from generate_series(1, 10);
select clear_username_sign_in_failures('ann_test_107');
select lives_ok($$ select email_for_username('ann_test_107') $$, 'a successful sign-in starts the count again');

-- Unknown usernames are limited the same way, so they can't be told apart.
select record_username_sign_in_failure('nobody_test_107') from generate_series(1, 10);
select throws_ok($$ select email_for_username('nobody_test_107') $$, 'PT429', null, 'unknown usernames are paused too');

reset role;
select is((select count(*)::int from cron.job where jobname = 'expire-username-sign-in-failures'), 1, 'old attempts are cleared daily');

select * from finish();
rollback;
