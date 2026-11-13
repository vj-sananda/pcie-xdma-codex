#!/usr/bin/env bash
# Remove only the expected FPGA endpoint before a volatile JTAG reconfiguration.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $# == 1 && $1 =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] || exit 2
device=/sys/bus/pci/devices/$1
[[ -d $device && $(cat "$device/vendor") == 0x10ee ]] || {
    echo 'Refusing to remove a device that is not the expected Xilinx FPGA.' >&2; exit 1;
}
shopt -s nullglob
nodes=(/dev/xdma*)
if ((${#nodes[@]})) && fuser "${nodes[@]}"; then
    echo 'DMA device is open in another process; close it before reprogramming.' >&2
    exit 1
fi
lspci -Dnnvv -s "$1"
printf '1\n' > "$device/remove"
[[ ! -e $device ]] || { echo 'Endpoint removal failed.' >&2; exit 1; }
echo "FPGA_DETACH_PASS: $1"
