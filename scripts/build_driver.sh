#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=a918c5196a09f95756af244a607d543d9dce5bfb
if [[ ! -d vendor/dma_ip_drivers/.git ]]; then
    git clone https://github.com/Xilinx/dma_ip_drivers.git vendor/dma_ip_drivers
    git -C vendor/dma_ip_drivers checkout "$revision"
fi
if [[ $(git -C vendor/dma_ip_drivers rev-parse HEAD) != "$revision" ]]; then
    echo "Driver checkout differs from tested commit $revision; refusing to overwrite it." >&2
    exit 1
fi
mkdir -p reports
make -C vendor/dma_ip_drivers/XDMA/linux-kernel/xdma -j4 2>&1 | tee reports/driver_build.log
make -C vendor/dma_ip_drivers/XDMA/linux-kernel/tools -j4 2>&1 | tee reports/driver_tools_build.log
