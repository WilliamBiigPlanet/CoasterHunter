#!/usr/bin/env bash
# Double-click this in Finder to run the first-time setup.
#
# macOS treats a .command file as launchable: double-clicking opens Terminal and
# runs it, so no typing is needed. It just calls setup.sh, which is the same
# thing you would run from a terminal yourself.

cd "$(dirname "$0")"
./setup.sh
status=$?

echo
if [ $status -eq 0 ]; then
  echo "Setup finished. You can close this window."
else
  echo "Setup stopped with an error above. Leave this window open and show it to Claude."
fi
echo
read -r -p "Press Return to close."
