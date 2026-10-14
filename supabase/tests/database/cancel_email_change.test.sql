-- Cancelling a pending email change.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Ann and Ben both have a change pending (as Supabase Auth leaves it after updateUser).
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        email_change, email_change_token_new, email_change_token_current,
                        email_change_confirm_status, email_change_sent_at) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ann@example.test', '{"username":"ann"}', 'ann.new@example.test', 'tok-new-ann', 'tok-cur-ann', 1, now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ben@example.test', '{"username":"ben"}', 'ben.new@example.test', 'tok-new-ben', 'tok-cur-ben', 0, now());

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role anon;
select throws_ok('select public.cancel_email_change()', '42501', null, 'signed-out callers can''t cancel');

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok('select public.cancel_email_change()', 'a user can cancel their own pending change');

reset role;
select is((select email_change from auth.users where id = '11111111-1111-1111-1111-111111111111'), '',
          'the pending address is cleared');
select is((select email_change_token_new || email_change_token_current from auth.users
            where id = '11111111-1111-1111-1111-111111111111'), '',
          'both confirmation tokens are cleared, so the links already sent stop working');
select is((select email_change_confirm_status from auth.users where id = '11111111-1111-1111-1111-111111111111'), 0::smallint,
          'a half-confirmed change is reset');
select is((select email from auth.users where id = '11111111-1111-1111-1111-111111111111'), 'ann@example.test',
          'the current email is unchanged');
select is((select email_change from auth.users where id = '22222222-2222-2222-2222-222222222222'), 'ben.new@example.test',
          'other users'' pending changes are untouched');

select * from finish();
rollback;
