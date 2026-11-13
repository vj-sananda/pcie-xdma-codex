#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p reports
case "${1:-}" in
  build|build_pcie_diagnostics|read_pcie_diagnostics|program|test_jtag|probe_hardware|backup_flash|prepare_flash|program_flash|restore_flash|check_pcie_constraints)
    action=$1
    vivado -mode batch -source "scripts/$action.tcl" \
      -log "reports/$action.log" -journal "reports/$action.jou" -tclargs "${@:2}" \
      2>&1 | tee "reports/$action.console.log"
    # Vivado can exit zero after some Tcl failures; require an explicit success marker.
    case "$action" in
      build) marker=BUILD_PASS ;;
      build_pcie_diagnostics) marker=PCIE_DIAGNOSTIC_BUILD_PASS ;;
      read_pcie_diagnostics) marker=PCIE_DIAGNOSTIC_READ_PASS ;;
      program) marker=PROGRAM_PASS ;;
      test_jtag) marker=JTAG_TEST_PASS ;;
      probe_hardware) marker='DEVICE: xc7k480t_0' ;;
      backup_flash) marker=FLASH_BACKUP_PASS ;;
      prepare_flash) marker=FLASH_IMAGE_PASS ;;
      check_pcie_constraints) marker=PCIE_CONSTRAINTS_PASS ;;
      program_flash)
        if [[ ${2:-} == --check ]]; then marker=FLASH_PREFLIGHT_PASS
        else marker=FLASH_BOOT_PASS
        fi ;;
      restore_flash)
        if [[ ${2:-} == --check ]]; then marker=FLASH_RESTORE_PREFLIGHT_PASS
        else marker=FLASH_RESTORE_PASS
        fi ;;
    esac
    grep -q "^$marker" "reports/$action.log"
    if [[ $action == backup_flash ]]; then
      grep -q '^SRAM_RESTORE_PASS' "reports/$action.log"
    fi
    ;;
  test_dma)
    python3 scripts/test_dma.py 2>&1 | tee reports/test_dma.log
    ;;
  test_pcie_registers)
    python3 scripts/test_pcie_registers.py 2>&1 | tee reports/test_pcie_registers.log
    ;;
  *) echo "Usage: $0 {probe_hardware|build|build_pcie_diagnostics|read_pcie_diagnostics|program [bitstream]|test_jtag|test_dma|test_pcie_registers|check_pcie_constraints|backup_flash|prepare_flash|program_flash --check|program_flash --write|restore_flash --check|restore_flash --write}" >&2; exit 2 ;;
esac
