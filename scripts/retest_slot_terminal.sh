#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
bash scripts/retest_slot.sh 2>&1 | tee reports/slot_retest.console.log
result=$?
printf '%s\n' "$result" > reports/slot_retest.exit
printf '\nRetest exit status: %s\nPress Enter to close.\n' "$result"
read -r
