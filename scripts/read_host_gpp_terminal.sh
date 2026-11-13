#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
printf 'Reading chipset PCIe state using the firmware RDAB method.\n'
printf 'Only the indirect read selector is written; port settings are not changed.\n'
sudo python3 scripts/read_host_gpp.py 2>&1 | tee reports/host_gpp_collection.log
result=$?
printf '%s\n' "$result" > reports/host_gpp_collection.exit
printf '\nCollector exit status: %s\nPress Enter to close.\n' "$result"
read -r
