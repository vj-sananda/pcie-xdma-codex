# PCIe clock and link-training diagnostics

These diagnostics were developed for the earlier failure in the lower black
slot. On November 12, the original baseline bitstream passed Gen2 x8 PCIe and
DMA in the upper blue x16 slot; see [RESULTS.md](RESULTS.md). Further diagnostic
programming is unnecessary for that working configuration.

In the earlier lower-slot tests, the baseline status reported
`PERST#=1`, `link_up=0`, and `dma_resetn=0`; those bits alone cannot distinguish
a missing PCIe reference clock, incomplete transceiver reset, or failed link
training.

`scripts/build_pcie_diagnostics.tcl` creates a separate diagnostic image from
the routed baseline. It adds ordinary registers and multiplexers and uses the
existing JTAG AXI master. Vivado 2026.1 BASIC rejected `create_debug_core` for an
ILA, so this implementation does not instantiate an ILA. Build and hardware
validation status are recorded in [RESULTS.md](RESULTS.md).

## Build

```bash
cd /home/vsananda/work/pcie-xdma-codex
source /opt/2026.1/2026.1/Vivado/settings64.sh
./scripts/run.sh build_pcie_diagnostics
```

The input is `build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_routed.dcp`.
Outputs are `build/accelerator_pcie_diagnostic.{dcp,bit}`. The script requires
passing timing, bus-skew checks, DRC, and the actual routed PCIe pin/lane audit
before reporting `PCIE_DIAGNOSTIC_BUILD_PASS`. Reports have the
`reports/pcie_diagnostic_` prefix. The baseline bitstream is preserved. A separate `*_unvalidated.dcp` is saved
before the final checks for build recovery; do not treat it as a passing artifact.

The 84 observation bits use 77 two-register synchronizers clocked by the
independent 50 MHz oscillator. All eight receiver-detect inputs share one
source, so they share one synchronizer. Both registers have `ASYNC_REG`; only the first
stage's D pin receives a new false-path exception. The second stage, page mux,
and GPIO input register remain timed. No PCIe reset, lane, clock, FIFO, or DMA
configuration is changed.

## Capture on the board

Arrange exclusive board/JTAG access before using these commands. Another
session may be testing a different image. This is a volatile download. If the
FPGA is enumerated, first stop its clients and detach it as described in
[HOWTO.md](HOWTO.md#download-and-test-over-jtag). These commands do not write flash.

```bash
./scripts/run.sh program build/accelerator_pcie_diagnostic.bit
./scripts/run.sh test_jtag
./scripts/run.sh read_pcie_diagnostics
```

The reader checks the page-7 signature three times, verifies that the page-0
counter advances, and collects 20 rounds of pages 1–6. Raw observations are
timestamped in `reports/pcie_diagnostics_YYYYMMDD_HHMMSS.tsv`. Each page is read
at a different time. The command prints clock lock, link state, and per-lane
reset/idle masks, then returns the LEDs and page selector to zero. Its
`PCIE_DIAGNOSTIC_READ_PASS` marker means the observations were collected; it
does not certify link establishment or DMA.

The selector is the existing three-bit LED register at address `0x00000000`.
Read status at `0x00000008`; extract a page as `(status >> 6) & 0x3ffff`.
The high byte remains `0xC7`. Bits 5:3 still show the LED/selector value,
bit 2 is DMA reset released, bit 1 is PERST#, and bit 0 is link-up.
Selecting pages also changes the physical user LEDs.

| Page | Payload bits | Meaning |
| --- | --- | --- |
| 0 | 17:0 | Original advancing counter |
| 1 | 5:0 | Hard-block `PLLTSSMSTATE` |
| 1 | 6 | PCIe MMCM `LOCKED` |
| 1 | 7 | Hard-block `PLPHYLNKUPN` (active low) |
| 1 | 8 | Hard-block `PLSELLNKRATE` raw value |
| 1 | 10:9 | Hard-block `PLSELLNKWIDTH` raw value |
| 1 | 11 | Hard-block `SYSRSTN`: high means its system reset is released |
| 2 | 7:0 / 15:8 | Lane 0–7 `CPLLLOCK` / `TXRESETDONE` |
| 3 | 7:0 / 15:8 | Lane 0–7 `RXRESETDONE` / `RXELECIDLE` |
| 4 | 7:0 / 15:8 | Lane 0–7 `TXDETECTRX` / `TXELECIDLE` |
| 5 | 11:0 | Three-bit `RXSTATUS` per lane 0–3; lane 0 in bits 2:0 |
| 5 | 12 / 13 / 14 | Sticky receiver-detect / nonzero LTSSM / core reset release seen |
| 6 | 11:0 | Three-bit `RXSTATUS` per lane 4–7; lane 4 in bits 2:0 |
| 7 | 17:0 | Fixed diagnostic signature `0x2D15B` |

Sticky bits clear only when the FPGA is configured and are set from synchronized
50 MHz observations; very short pulses can still be missed. Nonzero-LTSSM seen
is evidence of activity, not proof of successful training. Unused payload bits are zero. The source pin for every sampled bit and the
GPIO destination pins are recorded in `reports/pcie_diagnostic_map.rpt`.

## Interpret the evidence

The corrected image was programmed and measured on November 11 at 22:17:59.
All PLL locks and TX/RX reset-done bits were high, and hard-block SYSRSTN was
high. Sticky flags recorded receiver detection and nonzero LTSSM activity,
although every current-state sample showed LTSSM=0, all RX lanes idle, and
link down. Thus this image gets through PHY initialization and attempts
training; a persistently asserted core reset does not explain the missing
link. Linux still exposes no Xilinx endpoint. See the timestamped logs and
capture JSON listed in RESULTS.md.

- Stable CPLL/MMCM lock bits distinguish working PLLs from a clock or reset
  condition that prevents lock. Lack of lock alone does not prove a missing
  physical clock; PLL reset and power-down conditions also matter.
- With lock established, TX/RX reset completion and LTSSM observations narrow
  the investigation to transceiver initialization or link training.
- The generated PCIe HDL explicitly identifies LTSSM value `0x16` as L0.
  Confirm it together with the link bits and Linux enumeration, rather than
  interpreting a single sample as success.
- The lower black ASUS M5A97 R2.0 slot is wired for x4. Traffic on lanes 4–7
  is not required for an x4 link; do not require all eight receive lanes to
  leave electrical idle.

These are asynchronous status snapshots, not a waveform capture. Two-stage
synchronization reduces metastability risk but does not make a multi-bit state
transition atomic. Short pulses can be missed, and a state read during a
transition can be incoherent. Use repeated stable values to guide the next
test; the reader cannot measure reference-clock frequency or establish the
exact order of training events. A later coherent capture in the PCIe clock
domain may be needed if stable snapshots are inconclusive.

Once `lspci -Dnn -d 10ee:7021` shows the endpoint, continue with the driver and
hardware DMA procedure in [HOWTO.md](HOWTO.md). That procedure passed with exact
payload comparisons on November 12 using the baseline image in the upper slot.

## Development-image compatibility

The measured 21:55:10 image has reversed payload bits in CPU bits 25:8, because
AXI GPIO's internal register numbering is ascending. It is preserved as
`build/accelerator_pcie_diagnostic_legacy_215510.bit` and requires
`./scripts/run.sh read_pcie_diagnostics --legacy-reversed-gpio`. That explicit
mode verifies its old page-7 signature `0x2D15A` and decodes its known mapping.
It has no hard-block reset or sticky-activity fields. Do not use this option
for the corrected image or interpret its raw fields using the main map above.
The corrected source verifies each original counter driver and final mux
destination and uses signature `0x2D15B`. Consult RESULTS.md for build/test status.
