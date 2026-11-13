#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
printf 'Collecting PCIe, firmware slot, and kernel evidence. No settings will change.\n'
sudo python3 scripts/collect_host_pcie.py 2>&1 | tee reports/host_pcie_collection.log
result=$?
printf '%s\n' "$result" > reports/host_pcie_collection.exit
printf '\nCollector exit status: %s\nPress Enter to close.\n' "$result"
read -r
