# Recover host boot after accelerator flash programming

This records the November 11 recovery after the user reported a blank screen
and apparent failure to reach POST with the accelerator flash image. The card
receives power only from its PCIe slot. The flash was restored as recorded
below. On November 12, after the card moved to the upper blue x16 slot, Linux
was running and a fresh baseline SRAM download passed Gen2 x8 PCIe and DMA;
see [RESULTS.md](RESULTS.md). The failed flash image's cold boot has not been
revalidated, and its exact failure cause remains unproven.

The original full 64 MiB flash backup is intact:
`backups/flash_before_20261111_195055.bin`, SHA-256
`9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90`.
`build/restore_original_boot_blocks.mcs` contains exactly its first 4 MiB,
covering all 16 erase blocks changed by the accelerator image. Its Intel HEX
records have been decoded and compared byte-for-byte with the original backup.
Restoration completed at 21:10:39 on November 11, 2026. A new full 64 MiB
readback exactly matches the original backup hash. Evidence is in
`reports/restore_flash.log` and `reports/flash_recovery_result.json`.
This proves the contents at the restoration time. The November 12 retest did
not reread or write flash, so it does not establish current flash contents or
validate persistent boot of this project's accelerator.

## Regain powered JTAG access using SW1

The [board author's guide](https://www.tiferking.cn/index.php/2024/12/19/650/)
identifies SW1 as connected to INIT_B; SW2 is a user GPIO button.
AMD/Xilinx UG470 v1.13.1, page 84, states that INIT_B held low during
initialization delays configuration, and that pulling it low after it has gone
high cannot delay configuration. Page 67 describes the same hold-from-power-on
method for Master BPI. A local copy is `reports/ug470_verified.pdf` with its
retrieval URL in `reports/ug470_source.txt`.

1. Shut down the PC, disconnect mains power, and wait for board LEDs to go out.
2. Install the FPGA and connect JTAG with power disconnected. Do not hot-plug
   the PCIe card. The USB/JTAG cable does not power the card.
3. Press and hold the clearly labeled **SW1 before restoring power**. While
   touching only the button, restore mains power and turn on the PC. Keep SW1
   held until Linux reaches the login screen or desktop.
4. Release SW1 only after Linux has booted. This permits the flash image to
   load. If the PC remains responsive, reconnect to the session for restoration.

The user successfully booted Linux with SW1 held and confirmed that Linux
remained responsive after releasing it. This regained JTAG access for the
completed recovery. If the PC still hangs with SW1 held, or hangs when it is
released, power down. The fallback is
JTAG from a second computer while the affected PC supplies slot power; its own
Linux need not be running. Do not improvise jumpers or short configuration pins.

## Restore the changed blocks

Once Linux and powered JTAG access are available, verify the target and perform
the recovery with the prepared scripts:

```bash
cd /home/vsananda/work/pcie-xdma-codex
source /opt/2026.1/2026.1/Vivado/settings64.sh
python3 scripts/prepare_flash_recovery.py
./scripts/run.sh restore_flash --check
./scripts/run.sh restore_flash --write
```

`--check` checks backup/image/script hashes and selects the memory; it performs
no flash operations. `--write` loads Vivado's flash-access helper, restores only
addresses `0x00000000`–`0x003FFFFF`, and verifies programming. It then reads all
64 MiB to a new timestamped backup and requires its SHA-256 to match the full
original backup before printing `FLASH_RESTORE_PASS`. Full readback took about
8.5 minutes during the initial backup. Do not run other JTAG operations during
restoration.

The script leaves the flash helper in SRAM and does not reload the accelerator.
After verified restoration, a coordinated cold power cycle without holding SW1
can test whether the original PC boot behavior is restored. Flash-byte recovery
alone does not prove host boot recovery. If restoration fails, retain its log
and the original backup; do not run the accelerator flash-write command again.
