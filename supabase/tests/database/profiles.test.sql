-- Profile editing, avatars storage rules, shared groups, own stats.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test', '{"username":"cat"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- Ann and Ben share "Crew"; Ann also has "Solo"; Cat shares nothing.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Solo', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

-- Editing your own profile
select lives_ok($$ update profiles set bio = 'Weekend hiker', display_name = 'Ann L', username = 'ann_l'
                   where id = auth.uid() $$, 'edit own bio, display name and username');
select is((select username from profiles where id = auth.uid()), 'ann_l', 'username changed');
select throws_ok($$ update profiles set username = 'ben' where id = auth.uid() $$, '23505', null,
                 'taken usernames are rejected');
select throws_ok($$ update profiles set username = 'Bad Name' where id = auth.uid() $$, '23514', null,
                 'invalid usernames are rejected');
select throws_ok($$ update profiles set bio = repeat('x', 161) where id = auth.uid() $$, '23514', null,
                 'bio is at most 160 characters');
update profiles set bio = 'hacked' where id = '22222222-2222-2222-2222-222222222222';
select is((select bio from profiles where id = '22222222-2222-2222-2222-222222222222'), null,
          'cannot edit someone else''s profile');

-- Shared groups and stats
select is((select count(*)::int from shared_groups(auth.uid())), 2, 'own: all my groups');
select is((select group_name from shared_groups('22222222-2222-2222-2222-222222222222')), 'Crew',
          'with Ben: only the group we share');
select is((select count(*)::int from shared_groups('33333333-3333-3333-3333-333333333333')), 0,
          'with Cat: nothing shared');

insert into activities (id, name) values ('b0000000-0000-0000-0000-000000000001', 'Hike');
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Future plan', false, null,
  now() + interval '1 day', now() + interval '1 day 2 hours', null);
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Past plan', false, null,
  now() - interval '2 days', now() - interval '2 days' + interval '1 hour', null);
select is((select row(groups, activities, upcoming_plans)::text from my_profile_stats()), '(2,1,1)',
          'stats: 2 groups, 1 activity, 1 upcoming plan');

-- Avatar storage: write only in your own folder
select lives_ok($$ insert into storage.objects (bucket_id, name, owner)
                   values ('avatars', '11111111-1111-1111-1111-111111111111/me.jpg', auth.uid()) $$,
                'upload to own avatar folder');
select throws_ok($$ insert into storage.objects (bucket_id, name, owner)
                    values ('avatars', '22222222-2222-2222-2222-222222222222/me.jpg', auth.uid()) $$,
                 '42501', null, 'cannot upload into someone else''s folder');
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from storage.objects
           where bucket_id = 'avatars' and name = '11111111-1111-1111-1111-111111111111/me.jpg'), 1,
          'any signed-in user can see avatars');

select * from finish();
rollback;
