-- Local development data. Loaded by `supabase db reset`; never runs against a hosted project.
--
-- Test accounts (password for both: devpass123):
--   dev_alice  alice@dev.test
--   dev_bob    bob@dev.test

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       extensions.crypt('devpass123', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}',
       jsonb_build_object('username', u.username, 'display_name', u.display_name),
       now(), now(), '', '', '', ''
from (values
  ('a0000000-0000-0000-0000-00000000000a'::uuid, 'alice@dev.test', 'dev_alice', 'Alice'),
  ('b0000000-0000-0000-0000-00000000000b'::uuid, 'bob@dev.test',   'dev_bob',   'Bob')
) as u (id, email, username, display_name);

insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
select gen_random_uuid(), id, id::text, jsonb_build_object('sub', id::text, 'email', email), 'email', now(), now(), now()
from auth.users
where email in ('alice@dev.test', 'bob@dev.test');
