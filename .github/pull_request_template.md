Closes #

## What

## Why

## Testing

- [ ] `flutter analyze` clean, `flutter test` passes
- [ ] `supabase test db` passes (new rules have pgTAP tests)
- [ ] Tried it in the app (what you clicked through)

## Notes for reviewers

- [ ] New migrations? Run `supabase db push` on the cloud project **before the next deploy** (merging doesn't deploy; deploys run on request)
- [ ] Edge Function changed? Owner runs `supabase functions deploy <name>` (and `supabase secrets set` for new keys) before the next deploy
- [ ] Email template changed? Paste it into the Supabase dashboard (docs/deployment.md §1)
- [ ] Other dashboard steps (Google Cloud, Netlify, GitHub secrets)? Listed here and in docs/deployment.md

<!-- Docs updated (features.md, endpoints.md, database.md, SPEC.md, decisions.md, deployment.md, handover.md)? -->
