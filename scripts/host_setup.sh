#!/usr/bin/env bash
# Run AFTER programming: sudo bash scripts/host_setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $EUID -ne 0 ]]; then
    echo 'Run with sudo: bash scripts/host_setup.sh' >&2
    exit 1
fi
printf '1\n' > /sys/bus/pci/rescan
lspci -Dnn -d 10ee:7021
if ! lspci -Dn -d 10ee:7021 | grep -q .; then
    echo 'No 10ee:7021 endpoint: check slot, PCIe link status, and firmware resource allocation.' >&2
    exit 1
fi
if ! test -d /sys/module/xdma; then
    insmod vendor/dma_ip_drivers/XDMA/linux-kernel/xdma/xdma.ko
fi
udevadm settle
# Restrict test access to the invoking user instead of making DMA world writable.
if [[ -n ${SUDO_USER:-} ]]; then
    for node in /dev/xdma*; do
        [[ -c "$node" ]] || continue
        chown "$SUDO_USER" "$node"
        chmod 600 "$node"
    done
fi
lspci -vv -d 10ee:7021
ls -l /dev/xdma*
