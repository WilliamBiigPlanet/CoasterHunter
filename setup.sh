#!/usr/bin/env bash
# First-run setup after cloning CoasterHunter.
#
# The seed database is generated rather than committed — it is 7 MB and would
# change on every pipeline run — so a fresh clone needs this before the app has
# any data to read.
#
#   ./setup.sh

set -euo pipefail
cd "$(dirname "$0")"

step() { printf "\n\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

step "Checking what's installed"

if ! command -v node >/dev/null; then
  warn "Node is not installed. Get it from https://nodejs.org (choose the LTS build)."
  exit 1
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -lt 22 ]; then
  warn "Node $(node -v) is too old — the pipeline uses the built-in SQLite module added in 22.5."
  warn "Update from https://nodejs.org and run this again."
  exit 1
fi
ok "Node $(node -v)"

if command -v swift >/dev/null; then
  ok "Swift $(swift --version 2>&1 | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')"
else
  warn "Swift not found — install Xcode, or Command Line Tools with: xcode-select --install"
fi

if command -v xcodegen >/dev/null; then
  ok "XcodeGen $(xcodegen --version 2>&1 | head -1)"
else
  warn "XcodeGen not installed. It generates the Xcode project:"
  warn "    brew install xcodegen"
fi

step "Building the seed database"
echo "  Fetching from ThemeParks.wiki, Wikipedia and Wikidata."
echo "  Around two minutes the first time; seconds afterwards, from cache."
( cd pipeline && node build.mjs )

step "Copying it into the app"
./pipeline/copy-seed.sh

step "Running the tests"
( cd pipeline && node --test test.mjs >/dev/null 2>&1 && ok "pipeline: 19 tests passed" ) \
  || warn "pipeline tests failed — run 'cd pipeline && node --test test.mjs' to see why"

( cd CoasterHunter/Packages/CoasterHunterCore && ./Tools/run-tests.sh >/dev/null 2>&1 \
  && ok "core: 61 tests passed" ) \
  || warn "core tests failed — run CoasterHunter/Packages/CoasterHunterCore/Tools/run-tests.sh to see why"

step "Next"
if command -v xcodegen >/dev/null; then
  echo "  cd CoasterHunter && xcodegen generate && open CoasterHunter.xcodeproj"
else
  echo "  brew install xcodegen"
  echo "  cd CoasterHunter && xcodegen generate && open CoasterHunter.xcodeproj"
fi
echo
echo "  The Design Style Reference folder is not in the repo — copy it across"
echo "  separately if you want the visual reference to hand."
