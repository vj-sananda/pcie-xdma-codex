#!/usr/bin/env bash
# Run from a desktop terminal so sudo authentication stays in that terminal.
set -eo pipefail
cd "$(dirname "$0")/.."
source /opt/2026.1/2026.1/Vivado/settings64.sh
set -u
run_dir=reports/slot_retest_$(date +%Y%m%d_%H%M%S)
mkdir -p "$run_dir"
printf '%s\n' "$run_dir" > reports/slot_retest_latest.txt
cat /proc/sys/kernel/random/boot_id > "$run_dir/boot_id.txt"
printf '%s  %s\n' \
    95ecc03eabab65a94e1e00c743be95df3ca616fbb54eb1a8e78d556a02e99d52 \
    build/accelerator.bit | sha256sum -c -
lspci -Dnn > "$run_dir/pci_before.txt"
mapfile -t endpoints < <(lspci -Dn -d 10ee: | awk '{print $1}')
[[ ${#endpoints[@]} == 1 ]] || { echo 'Expected exactly one Xilinx endpoint.' >&2; exit 1; }
echo 'Administrator access is needed to detach and rediscover the FPGA endpoint.'
sudo bash scripts/detach_fpga.sh "${endpoints[0]}" | tee "$run_dir/detach.log"
./scripts/run.sh program build/accelerator.bit
cp reports/program.log "$run_dir/program.log"
./scripts/run.sh test_jtag
cp reports/test_jtag.log "$run_dir/test_jtag.log"
grep -q '^PCIE_STATUS: link_up=1 perstn=1 dma_resetn=1 ' "$run_dir/test_jtag.log" || {
    echo 'FPGA functional test finished, but PCIe link is not up.' >&2; exit 1;
}
sudo bash scripts/host_setup.sh | tee "$run_dir/host_setup.log"
lspci -Dnn > "$run_dir/pci_after.txt"
./scripts/run.sh test_dma
cp reports/test_dma.log reports/dma_results.json "$run_dir/"
./scripts/run.sh test_pcie_registers
cp reports/test_pcie_registers.log reports/pcie_register_results.json "$run_dir/"
echo "SLOT_RETEST_PASS: $run_dir"
