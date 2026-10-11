#!/usr/bin/env bash
# Release builds pointed at the hosted backend.
#   ./scripts/build.sh web       → app/build/web (upload to Netlify)
#   ./scripts/build.sh android   → app/build/app/outputs/bundle/release/app-release.aab
#   ./scripts/build.sh ios       → app/build/ios/ipa (needs Xcode signing set up)
# Reads app/env/prod.json (copy from prod.example.json). See docs/deployment.md.
set -euo pipefail
cd "$(dirname "$0")/../app"

env_file="env/prod.json"
if [[ ! -f "$env_file" ]]; then
  echo "Missing app/$env_file. Copy env/prod.example.json and fill it in." >&2
  exit 1
fi
if grep -q '<' "$env_file"; then
  echo "app/$env_file still has <placeholders>." >&2
  exit 1
fi

defines=(--dart-define-from-file="$env_file")
case "${1:-}" in
  web)
    flutter build web --release "${defines[@]}"
    ;;
  android)
    host=$(python3 -c "import json,urllib.parse;print(urllib.parse.urlparse(json.load(open('$env_file'))['APP_URL']).hostname)")
    flutter build appbundle --release "${defines[@]}" -PappLinkHost="$host"
    ;;
  ios)
    flutter build ipa --release "${defines[@]}"
    ;;
  *)
    echo "Usage: $0 web|android|ios" >&2
    exit 1
    ;;
esac
