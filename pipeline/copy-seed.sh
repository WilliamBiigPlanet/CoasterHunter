#!/usr/bin/env bash
# Copy the freshly-built seed database into the app bundle.
#
# The database is generated, not authored, so it is kept out of git — this is
# the step that puts it where the app expects it after a build or a fresh clone.

set -euo pipefail
cd "$(dirname "$0")"

SOURCE="out/coasterhunter-seed.sqlite"
DEST="../CoasterHunter/App/Resources/coasterhunter-seed.sqlite"

if [ ! -f "$SOURCE" ]; then
  echo "No seed database yet. Run 'npm run build' first." >&2
  exit 1
fi

cp "$SOURCE" "$DEST"
echo "copied $(du -h "$SOURCE" | cut -f1) → $DEST"
