# Link verification files

Templates for the files that let invite links (`https://<APP_URL host>/join/<token>`)
open the installed phone apps. Fill in the placeholders, then copy them to
`app/web/.well-known/` so they're published with the web app:

- `assetlinks.json`: Android. SHA-256 fingerprint from Play Console → Setup → App signing.
- `apple-app-site-association`: iOS. Your Apple Developer Team ID.

They aren't in `web/.well-known/` yet because publishing placeholders would make
link verification fail. Steps: `docs/deployment.md`.
