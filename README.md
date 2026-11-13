# ControlPaths Kintex-7 accelerator

Reproducible Vivado 2026.1 implementation of [Getting started with the Ebay's
Kintex7 Accelerator](https://www.controlpaths.com/2025/05/18/kintex7-accelerator/).
Target: YPCB-00338-1P1, XC7K480T-2FFG1156.

The design implements PCIe Gen2 x8 XDMA, a 128-bit AXI Stream FIFO loopback,
three LEDs through AXI GPIO, and the LM73 through AXI IIC. A JTAG AXI master
and independent 50 MHz register domain provide hardware diagnostics.

See [the complete how-to](docs/HOWTO.md) for prerequisites, design details,
building, programming, Linux setup, tests, and troubleshooting.
See [measured results](docs/RESULTS.md) for what actually ran on this board.

**Validated on hardware, November 12, 2026:** build and FIFO simulation pass;
the baseline bitstream was downloaded over JTAG; Linux enumerates `10ee:7021`
at **PCIe Gen2 x8**. All DMA loopbacks pass exact byte comparisons at 16 B,
4 KiB, 64 KiB, 1 MiB, and 4 MiB. GPIO and LM73 tests pass through both JTAG
and PCIe. Evidence: `reports/slot_retest_20261112_004428/`.

The working slot is the ASUS M5A97 R2.0's **upper blue x16 slot**. Earlier
tests in the lower black slot did not establish a link. Moving slots allowed
the existing baseline bitstream to work without constraint changes.

The normal flow is below. **Before programming an enumerated FPGA, stop its
clients and detach it with `sudo bash scripts/detach_fpga.sh <PCI-address>`**;
see the how-to for discovery and the automated repeat procedure.

```bash
source /opt/2026.1/2026.1/Vivado/settings64.sh
./scripts/run.sh build
./scripts/simulate_fifo.sh
./scripts/run.sh program
./scripts/run.sh test_jtag
./scripts/build_driver.sh
sudo bash scripts/host_setup.sh
./scripts/run.sh test_dma
./scripts/run.sh test_pcie_registers
```

Generated project and bitstream: `build/`. Logs and implementation reports:
`reports/`. The default `program` command downloads FPGA SRAM over JTAG; a power
cycle clears it. This successful test did not write flash. Persistent boot of
this accelerator is not validated; the earlier flash experiment and recovery
are retained in [the recovery record](docs/RECOVERY.md).
