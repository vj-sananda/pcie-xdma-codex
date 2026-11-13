# Validation record

**Build, download, and hardware tests passed.** The baseline accelerator was
programmed over JTAG and tested on November 12, 2026 (America/Chicago), after
the FPGA moved to the ASUS M5A97 R2.0's upper blue x16 slot. Linux enumerated
`10ee:7021` at **PCIe Gen2 x8**. All five DMA transfers returned exact matches.
The original baseline bitstream and its PCIe constraints were unchanged.

## Successful hardware run

Evidence directory: [`reports/slot_retest_20261112_004428/`](../reports/slot_retest_20261112_004428/).
The automated sequence exited 0 with `SLOT_RETEST_PASS`. PCIe register tests
were run separately immediately afterward and archived alongside it; the
repeat script now includes that step too.

| Check | Observed result | Evidence in run directory |
| --- | --- | --- |
| SRAM programming | PASS: DONE=1, CRC_ERROR=0 | `program.log` |
| JTAG identity/clock | PASS: signature C7 and advancing 50 MHz counter | `test_jtag.log` |
| JTAG GPIO | PASS: patterns 0, 1, 2, 4, 7, 5, 2, 0 | `test_jtag.log` |
| JTAG LM73 | PASS: address 0x4A, ID 0x0190; three readings of 42.750 °C | `test_jtag.log` |
| FPGA PCIe status | PASS: link_up=1, perstn=1, dma_resetn=1 | `test_jtag.log` |
| Linux enumeration | PASS: 0000:01:00.0, 10ee:7021, class 0580, XDMA bound | `host_setup.log` |
| Negotiated PCIe link | PASS: 5.0 GT/s, x8 | `host_setup.log`, `final_hardware_state.json` |
| DMA loopback | PASS: exact payload comparisons at all five sizes | `test_dma.log`, `dma_results.json` |
| PCIe AXI-Lite GPIO | PASS: identity, counter, link/reset state, eight LED patterns | `test_pcie_registers.log` |
| PCIe AXI-Lite LM73 | PASS: ID 0x0190; three readings of 43.500 °C | `pcie_register_results.json` |

| DMA payload | Result | Elapsed seconds |
| --- | --- | ---: |
| 16 B | Exact match | 0.006667 |
| 4 KiB | Exact match | 0.007775 |
| 64 KiB | Exact match | 0.006358 |
| 1 MiB | Exact match | 0.010957 |
| 4 MiB | Exact match | 0.032212 |

The receiver and transmitter ran concurrently with page-aligned buffers. The
larger transfers exceed the 64 KiB FPGA FIFO capacity. SHA-256 values are in
`dma_results.json`. Elapsed times include process startup, comparisons, and
file I/O; they are not measurements of peak PCIe throughput. LED tests check
FPGA output logic, not optical output. This is functional validation, not a
long-duration stress or electrical compliance test.

The existing endpoint before programming was `10ee:7028`, already at Gen2 x8.
Its image origin was not established. It was detached from Linux before the
baseline JTAG download, then the new `10ee:7021` endpoint was discovered by a
root PCIe rescan. This avoids keeping the driver attached while the image and
BAR layout change. Boot ID: `23c0aa32-f90e-4e28-b72d-40ade3005631`.

The working FPGA connects through root port `0000:00:02.0`, AMD 970 graphics
port `1002:5a16`. The GPU now connects through `0000:00:15.0`, SB950 PCIe port
`1002:43a0`, in the lower black slot; its observed link is Gen1 x4. The ASUS
manual specifies the upper slot as x16 electrical and lower as x4 electrical.
An x8 endpoint should normally negotiate down to x4. The earlier failed
lower-slot training and absent southbridge root port suggest a firmware/port
startup interaction, but the exact cause remains unproven. See
[the slot explanation](HOWTO.md#why-the-two-slots-behaved-differently).

Secure Boot was enabled. The already-loaded XDMA reference driver reported
version `2025.2.0`, source version `E1896DEC0BC5043CC17B09B`, matching the local
build. The loaded file's path and signing process were not established; no
module-signing or trust changes were made during this successful retest.
`modinfo xdma` alone can select a different, in-tree module with the same name,
so the evidence records `/sys/module/xdma` metadata.

## Build and simulation evidence

| Check | Observed result | Evidence |
| --- | --- | --- |
| Tools/target | Vivado 2026.1, valid BASIC license; XC7K480T-2FFG1156 | `reports/build.log` |
| Block design and synthesis | PASS; synthesis has zero errors/critical warnings | `reports/build.log` |
| Implementation | PASS: WNS +0.031 ns, WHS +0.016 ns; no failing setup/hold/pulse-width endpoints | `reports/timing_summary.rpt` |
| CDC bus skew | PASS: 16 constraints, minimum slack +11.243 ns | `reports/bus_skew.rpt` |
| Timing coverage | No unclocked register pins or unconstrained internal endpoints | `reports/timing_summary.rpt` |
| DRC | Zero errors; warnings retained | `reports/drc.rpt` |
| PCIe placement audit | PASS: 32 lane pins, GTX X0Y23–16, PCIe X0Y0, refclk J8/J7 and PERST# Y26 | `reports/pcie_constraints_audit.rpt` |
| Debug clock | PASS: independent sys_clk through sys_clk_IBUF_BUFG | `reports/debug_clock.log` |
| FIFO simulation | PASS: 12,000 words / 192,000 bytes; 4,641 input stalls; data, TKEEP, TLAST, stability and final empty checked | `reports/fifo_simulation.log` |
| XDMA driver/tools build | PASS against Linux 6.8.0-149-generic | `reports/driver_build.log`, `reports/driver_tools_build.log` |

Baseline resource use: 17,794 LUTs (5.96%), 21,440 registers (3.59%), 44.5 BRAM
tiles (4.66%), eight GTX channels, and one PCIe hard block. Build ran from
19:01:50 to 19:22:39 on November 11. Static timing passes with a small positive
margin. DRC retains ten PDCN-1569 generated-IP warnings, one RTSTAT-10 warning,
and three BRAM WRITE_FIRST advisories. Methodology retains six LUTAR-1 and one
XDCB-5 warnings. No severity overrides or warning waivers were applied.

Validated bitstream: `build/accelerator.bit`.
SHA-256: `95ecc03eabab65a94e1e00c743be95df3ca616fbb54eb1a8e78d556a02e99d52`.
Build/source hashes: `reports/SHA256SUMS`. Successful-run evidence hashes:
`reports/slot_retest_20261112_004428/SHA256SUMS` (paths relative to the project).

## Flash and historical bring-up

This successful run programmed **volatile SRAM only**. No flash was read or
written, and no restart was performed by the retest. Persistent cold boot of
this project's accelerator remains unvalidated; SRAM programming must be
repeated after a power cycle.

On November 11 an approved accelerator flash image passed programming,
verification, and JTAG-commanded reload, but the user then reported a blank
screen at host boot. Holding SW1 allowed recovery. The original full 64 MiB
flash was restored and independently verified byte-for-byte at 21:10:39.
Both backup and restoration readback have SHA-256
`9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90`.
That establishes the flash contents at restoration time; the later preexisting
7028 endpoint does not establish what flash currently contains.

The complete earlier sequence, including failed lower-slot attempts, license
recovery, constraint checks, flash recovery, and diagnostic images, is preserved
in [BRINGUP_HISTORY.md](BRINGUP_HISTORY.md). The read-only host collection at
23:10 succeeded; the later attempted firmware-mediated chipset read failed with
`open: Operation not permitted` and made no port-setting changes. Those reports
are retained under `reports/host_pcie_20261111_231031/` and
`reports/host_gpp_collection.log`. No further chipset debugging was needed for
the successful upper-slot test. Recovery instructions remain in
[RECOVERY.md](RECOVERY.md); the reproducible build/program/test procedure is in
[HOWTO.md](HOWTO.md).
