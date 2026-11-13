# Historical bring-up record: November 11, 2026

This is the preserved record before the successful slot move. Its pending,
current-state, and link-down statements describe November 11, not the current
board. The successful November 12 baseline download, Gen2 x8 link, and DMA
results are in [RESULTS.md](RESULTS.md).

Run date: November 11, 2026 (America/Chicago). Work in progress; pending steps
below are not reported as successes.

| Check | Observed result |
| --- | --- |
| JTAG discovery | PASS: Platform Cable USB II `00001173057801`, FPGA `xc7k480t_0`, IDCODE `23751093` |
| Vivado | 2026.1, build 6511674; valid BASIC license; synthesis license checkout succeeded |
| Block design validation | PASS |
| FIFO simulation | PASS: 12,000 words / 192,000 bytes; 4,641 input-stall cycles; data, TKEEP, TLAST, stability and final empty checked |
| XDMA driver compilation | PASS against Linux `6.8.0-149-generic` |
| XDMA host tools compilation | PASS |
| Synthesis | PASS: 0 errors, 0 critical warnings; 6 min 12 sec |
| Debug hub clock | PASS: connected to independent `sys_clk` through `sys_clk_IBUF_BUFG` |
| Implementation / bitstream | PASS: setup WNS +0.031 ns, hold WHS +0.016 ns; 0 failing setup/hold/pulse-width endpoints |
| CDC bus skew | PASS: 16 constraints, minimum slack +11.243 ns |
| Internal timing coverage | PASS: 0 unclocked register pins; 0 unconstrained internal endpoints |
| Bitstream DRC | PASS: 0 errors; warnings retained in reports |
| Routed PCIe board mapping | PASS: all 32 lane pins, lane-to-pad connectivity, GTX X0Y23–16, PCIe X0Y0, J8/J7 reference clock and Y26 PERST# match upstream |
| Programming | PASS: DONE=1, CRC_ERROR=0; 40 seconds at 6 MHz JTAG |
| JTAG identity / clock | PASS: signature C7, independent counter advances |
| LED register logic | PASS: patterns 0, 1, 2, 4, 7, 5, 2, 0 read back through status GPIO |
| LM73 hardware IIC | PASS: address `0x4A`, ID `0x0190`; three readings of 36.500 °C (`0x1240`) |
| PCIe physical link after programming | DOWN: link_up=0, PERST#=1, XDMA reset released=0 |
| Host PCIe rescan | Ran as root in a desktop terminal; no `10ee:7021` endpoint, setup exited 1 before driver loading |
| Host PCIe DMA test | NOT RUN: endpoint absent after rescan; driver not loaded |
| Flash backup | PASS: full 64 MiB read; independent 4096-byte header read matched; SRAM restored |
| BPI boot-image generation | PASS: compressed bitstream and MCS from the routed checkpoint; exact BPI x16 encoding checked |
| Boot image via JTAG | PASS: DONE/CRC and full JTAG functional test |
| Flash write preflight | PASS: backup/image hashes, part selection and image-only address range validated; no flash write performed |
| Flash programming and verification | PASS: approved image sectors erased, blank-checked, programmed and verified |
| Reload from flash through JTAG | PASS: DONE=1, CRC_ERROR=0, JTAG_AXI=1; subsequent functional test passed |
| Cold boot with new flash image | FAILED per user: blank screen, apparently before POST with card installed; exact stage and cause unproven |
| SW1 recovery boot | PASS per user: Linux booted with SW1 held, and remained responsive after release |
| Original flash restoration | PASS: first 4 MiB restored; independent full 64 MiB readback exactly matches original backup |
| Normal host boot after restoration | PENDING: verify with SW1 released |
| Separate PCIe diagnostic image | BUILD PASS at 22:14:10: corrected GPIO mapping; 84 observations through 77 synchronizers; setup +0.031 ns, hold +0.016 ns, 16 bus-skew checks pass, zero DRC errors; pin and CDC audits pass |
| Diagnostic image board capture | CAPTURE PASS at 22:17:59: all PLL locks and TX/RX reset-done bits high; hard-block reset released; sticky flags show receiver detection and LTSSM activity; current LTSSM=0 and link down in all 20 rounds |

Initial PCIe inventory contained no Xilinx endpoint. The FPGA's DONE bit was low
before programming. `sudo -n true` requires a password. Secure Boot is enabled,
and kernel lockdown is in integrity mode. The existing certificate at
`/var/lib/shim-signed/mok/MOK.der` is not enrolled according to `mokutil --test-key`;
no signing-key contents were read and no trust or boot settings were changed.

The first user-invoked host setup attempt failed before executing the script:
sudo reported that a terminal was required to read the password. The reported
pipeline exit code of 0 came from `tee`, not successful setup. The guide now uses
a desktop terminal and `set -o pipefail` so this failure cannot be mistaken for
successful setup. The user then authenticated in the desktop terminal, and the
script completed the rescan but found no endpoint. `reports/host_setup.log`
contains that latest attempt; `reports/host_setup.exit` records exit status 1.
The post-rescan PCIe inventory, boot ID, and absence of XDMA device nodes are
preserved in `reports/pcie_after_rescan.json`.

The JTAG test was repeated after the rescan and passed again. PCIe remained
`link_up=0 perstn=1 dma_resetn=0` (`C7753282`); LM73 readings were 39.000,
39.250, and 39.000 °C. This confirms that the design remains configured and
responding while the PCIe endpoint is absent.

The user authorized a warm restart at 19:38. Linux completed its shutdown path,
but the user reported that the computer hung and did not return to Linux. The
user then powered it off and on. Boot ID changed from
`03e0870d-3eaa-42d0-89b7-40a60ec04742` to
`d6c5a8cc-48b0-4c89-ac1f-7937d74c3374`; no FPGA PCIe endpoint appeared.
The cold-boot JTAG probe confirmed DONE=0 and mode pins M[2:0]=010 (Master BPI),
with x16 bus-width detection. See `reports/probe_after_power_cycle.log`.

After the user corrected the Vivado license setup, Vivado 2026.1 recognized its
BASIC license again. SRAM programming completed at 19:48:34 with DONE=1 and
CRC_ERROR=0. The JTAG test passed at 19:49:24; PCIe remained down
(`C7D05382`), and temperatures were 38.000, 38.250, and 38.000 °C. These runs are
preserved in `reports/program_after_power_cycle.log` and
`reports/test_jtag_after_power_cycle.log`.

The complete original flash is preserved as
`backups/flash_before_20261111_195055.bin` (67,108,864 bytes; SHA-256
`9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90`).
The read took 8 min 29 sec; an independent 4096-byte header read matched, and
the SRAM design was restored successfully. The backup contains 18,465,974
non-erased bytes. No flash erase or program operation was used for this backup.

`build/accelerator_boot.bit` and `build/accelerator_boot.mcs` are prepared from
the same routed checkpoint, with compression, Master BPI x16, asynchronous
reads, a 3 MHz configuration clock, and CCLK startup. The MCS payload is
3,962,176 bytes at `0x00000000`–`0x003C753F`. Every Intel HEX checksum and the
exact conversion from the bitstream were checked. The compressed image
programmed into SRAM in 9 seconds, and its JTAG functional test passed at
20:02:18. PCIe remained down (`C7CEA882`), with temperature readings 37.500,
37.500, and 37.750 °C. The memory-programming preflight passed without any
flash operation. Relevant evidence is in `reports/flash_artifacts.json`,
`reports/flash_artifacts.sha256`, `reports/program_boot_image.log`,
`reports/test_jtag_boot_image.log`, and `reports/flash_preflight.log`.
These preparation steps did not write flash. The subsequent authorized write
and boot test are recorded below.

The user then explicitly authorized programming flash and testing boot. The
write completed at 20:11:04 with `FLASH_PROGRAM_PASS` and `FLASH_BOOT_PASS`.
Vivado reported successful erase, blank check, programming, and verification;
the flash operation took 1 min 44 sec. The image occupies the first 16 erase
blocks (4 MiB, addresses `0x00000000`–`0x003FFFFF`); the full original 64 MiB
backup remains preserved. The FPGA reloaded from flash through `boot_hw_device`
without a new accelerator SRAM download, with DONE=1, CRC_ERROR=0, and one
JTAG AXI master. The functional JTAG test passed at 20:11:27: design identity,
clock counter, LED register patterns, and LM73 ID/temperature (37.250 °C in
all three samples). PCIe remained down (`C7FE4F42`: link=0, PERST#=1,
DMA reset released=0), and no `10ee:7021` endpoint appeared. Evidence is in
`reports/program_flash_verified.log`, `reports/test_jtag_after_flash_boot.log`,
and `reports/flash_boot_result.json`. This proves JTAG-commanded flash reload;
cold power-on configuration and boot-time PCIe enumeration were not established
by that JTAG-commanded reload.

After the subsequent power-cycle attempt, the user reported that the PC does
not boot with the FPGA installed: the screen stays blank, apparently before
POST. Linux is currently reachable in a later boot
(`3789815a-4e76-479d-b8d8-2cf2d6338203`); neither the FPGA PCIe endpoint nor the
USB programming cable was visible in the 20:40 check. The user confirmed that
the card receives power only from the slot and that SW1 is safely accessible.
The original backup hash was rechecked successfully. A recovery MCS containing
the exact original first 4 MiB was prepared locally; restoration followed as
recorded below. See `docs/RECOVERY.md`.

The user booted Linux with SW1 held and confirmed that releasing it after boot
left Linux responsive. The new boot ID is
`d3dce3e5-bed3-46b0-8592-573d1bd935bd`. The user also confirmed that the FPGA
is in the lower black full-length motherboard slot, and resumed the goal.
After the license was corrected for this boot, the JTAG restore preflight
passed. Restoration programmed and verified the original first 4 MiB, then
read back the entire 64 MiB in 8 min 30 sec. At 21:10:39 it passed the full
original-backup SHA-256 comparison. Readback is
`backups/flash_after_restore_20261111_210209.bin`; its SHA-256 is
`9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90`.
The full flash was restored byte-for-byte, and SRAM then held the flash-access
helper. Normal host startup without holding SW1 remains to be checked.
Logs and machine-readable results are `reports/restore_flash.log` and
`reports/flash_recovery_result.json`.

Logs are under `reports/`. `fifo_simulation.log` contains the actual simulation
success marker. `driver_build.log` and `driver_tools_build.log` contain the host
build output. No PCIe performance or hardware DMA success is implied by either
of those checks.

The user confirmed the FPGA is installed in this computer's PCIe slot. The host
currently exposes four PCIe root bridges, all occupied by the GPU, Ethernet,
and USB controllers; it exposes no additional empty PCIe root bridge. This is
consistent with firmware disabling a port when the FPGA was unconfigured at
boot, but does not by itself prove that diagnosis. The privileged PCIe rescan
did not change the topology. The subsequent warm-restart attempt hung, and the
user's power cycle cleared the volatile design. This does not prove that
firmware successfully reached PCIe enumeration with the design configured.
The new image was subsequently programmed into flash as recorded above.
No Secure Boot change has been made.

The ASUS M5A97 R2.0 English manual E7438 was retrieved from ASUS and checked
after the user's observation about spare PCIe connector contacts. Printed
pages ix and 1-14 explicitly specify the lower black PCIe 2.0 x16-length slot
as x4 electrically, and the upper blue slot as x16 electrically. The user had
confirmed that the FPGA occupies the lower black slot. Unused contacts beyond
an x8 card in an x16-length slot are normal; an x8 endpoint should negotiate
down to x4. This is the slot's documented capability, not an observed link
width, and does not establish the cause of the missing link. The downloaded
manual, extracted text, and source URL are in
`reports/asus_m5a97_r20_manual.{pdf,txt}` and
`reports/asus_m5a97_r20_manual_source.txt`. No slot changes, firmware changes,
or JTAG operations were performed during this check.

The PCIe warning in [TiferKing's board guide](https://www.tiferking.cn/index.php/2024/12/19/650/)
was checked against the actual routed checkpoint, including the manual
`pcie_port.xdc` in upstream commit
`8b13ecf71b7061dd43a2b1580f0caa469f64303f`. All 32 lane package pins match;
lane 0 through lane 7 occupy GTXE2_CHANNEL_X0Y23 through X0Y16 respectively.
Each GTX TX/RX positive/negative pin connects through its pad buffer to the
corresponding top-level lane. The PCIe hard block is PCIE_X0Y0, reference clock
pins are J8/J7 with a 10 ns constraint, and PERST# is Y26. The audit passed in
`reports/pcie_constraints_audit.rpt`. This rules out the specific missing or
incorrect lane-placement issue described by the author in this routed design;
it does not measure the physical reference clock or prove host-port enablement.
No placement or pin-constraint change was needed.

A separate diagnostic image preserves the Gen2 x8 XDMA/FIFO design and adds
synchronized PCIe observations to the independent JTAG status interface. The
user assigned JTAG programming and testing to this session. An ILA was not
used because this Vivado BASIC edition rejected `create_debug_core`; ordinary
registers and the existing JTAG AXI interface implement the observations.

The first diagnostic implementation at 21:34 was not programmed. CDC review
found duplicate synchronizers sampling the same receiver-detect signal. The
corrected implementation shares one synchronizer for that source. An intervening
build stopped at a Tcl variable collision in the pin audit; the audit now keeps
its variables local. The 21:55:10 build passed setup +0.031 ns, hold +0.016 ns,
16 bus-skew checks (minimum +11.311 ns), zero DRC errors, the PCIe mapping audit,
and all 76 two-stage synchronizer checks for 83 observations. There were no
critical CDC findings in the added diagnostics; two CDC-13 findings remained
within generated PCIe clock-switching logic. Its reports and source snapshots
are archived in `reports/diagnostic_build_20261111_215510/`.

That development image was programmed into SRAM at 21:56:29 with DONE=1 and
CRC_ERROR=0. SHA-256:
`105d3fbb85c16791f3a7728962e2a4571588d19781f3ebd89162d7619425d89c`.
The JTAG functional test passed at 21:57:08, including counter, LED registers,
and LM73 ID/temperature (37.750, 37.750, 38.000 °C). PCIe remained down with
PERST# high. Logs are `reports/program_pcie_diagnostic_20261111_215629.log`
and `reports/test_jtag_pcie_diagnostic_20261111_215708.log`.

The initial diagnostic reader rejected its page-7 signature, exposing a bit-order
mistake in the insertion script: AXI GPIO's internal VHDL register array is
ascending, so CPU bit `i` uses internal register `31-i`. The development image
put reversed diagnostic data in CPU bits 25:8 instead of 23:6. Page zero still
restored the original counter and signature. An explicit
`--legacy-reversed-gpio` reader option decoded this known layout and required
the correct fixed signature before collecting data; it did not silently relax
the final layout's checks. The installed AXI GPIO HDL confirms the ascending
array. The development image is preserved as
`build/accelerator_pcie_diagnostic_legacy_215510.{bit,dcp}`.

The legacy capture completed at 21:59:15: 120 page reads in 20 rounds all showed
MMCM lock=1, CPLL locks=FF, TXRESETDONE=FF, RXRESETDONE=FF, RXELECIDLE=FF,
TXDETECTRX=00, TXELECIDLE=FF, LTSSM=00, PHY link inactive, and all RXSTATUS fields
zero. All sampled link bits were low; no Xilinx endpoint appeared in Linux.
This establishes working PLL lock and completed transceiver reset, but does
not prove host-port enablement or exclude short training activity between
samples. Raw evidence is `reports/pcie_diagnostics_20261111_215910.tsv`; the
layout, exact image hash, and summary are in
`reports/pcie_diagnostic_capture_legacy.json`. Flash was not changed and Linux
remained responsive in the same boot.

The corrected image finished building at 22:14:10 with passing source-driver,
post-route GPIO destination, PCIe mapping, synchronizer, timing, bus-skew, and
DRC checks. It has 84 observations through 77 synchronizers, setup +0.031 ns,
hold +0.016 ns, and minimum bus-skew slack +11.243 ns. Build evidence is in
`reports/diagnostic_build_20261111_221410/`. Its SHA-256 is
`038b6192a934b810241fc7b9b80b39b391c5a38edeaaa3a0890737e6f0843b05`.

SRAM programming passed at 22:16:47 (DONE=1, CRC_ERROR=0), and the JTAG
functional test passed at 22:17:15, including three LM73 readings of 40.250 °C.
The normal diagnostic reader verified the corrected signature and mapping,
then captured 120 page reads in 20 rounds, finishing at 22:17:59. Every round
showed core reset released, MMCM/CPLL lock, and all TX/RX reset-done bits high.
All three sticky flags were set: receiver detection, nonzero LTSSM, and core
reset release had occurred since configuration. Current LTSSM was 0, all RX
lanes were electrically idle, and link remained down. No Xilinx endpoint
appeared in Linux. These results rule out a persistently asserted core reset
and show a training attempt; they do not establish why the host and endpoint
failed to link. Hardware DMA has not run.

Evidence: `reports/program_pcie_diagnostic_20261111_221647.log`,
`reports/test_jtag_pcie_diagnostic_20261111_221715.log`,
`reports/read_pcie_diagnostics_20261111_221759.log`,
`reports/pcie_diagnostics_20261111_221755.tsv`, and
`reports/pcie_diagnostic_capture_20261111_221759.json`. See
[PCIE_DIAGNOSTICS.md](PCIE_DIAGNOSTICS.md) for the verified register map.

Baseline resource use: 17,794 LUTs (5.96%), 21,440 registers (3.59%), 44.5 BRAM tiles
(4.66%), eight GTX channels, one PCIe hard block. Build started at 19:01:50 and
completed at 19:22:39 local time. The current SRAM image is the corrected diagnostic image built at 22:14:10; the
original flash remains restored. The baseline bitstream is preserved on disk.

Bitstream SHA-256:
`95ecc03eabab65a94e1e00c743be95df3ca616fbb54eb1a8e78d556a02e99d52`.
Full hashes are in `reports/SHA256SUMS`.

The DRC report contains 10 PDCN-1569 LUT-term warnings in generated IP, one
RTSTAT-10 warning for unused generated nets, and three BRAM WRITE_FIRST
advisories. Methodology reports six LUTAR-1 warnings inside AMD PCIe/debug IP and
one XDCB-5 warning about the efficiency of the custom synchronizer pin query.
No severity overrides or warning waivers were applied. Static timing passes
with a small positive margin; this is not a completed PCIe DMA validation.
