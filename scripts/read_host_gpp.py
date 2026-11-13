#!/usr/bin/env python3
"""Read SB900 GPP state through this board's existing ACPI RDAB method.

RDAB writes the indirect address selector, then reads its data port. This
script never calls WTAB/RWAB or writes a chipset configuration value.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run with sudo to access the kernel ACPI debugger.")
    root = Path(__file__).resolve().parents[1]
    captured = root / "reports/host_pcie_20261111_231031"
    expected = (captured / "acpi/DSDT.aml").read_bytes()
    actual = Path("/sys/firmware/acpi/tables/DSDT").read_bytes()
    if actual != expected:
        raise SystemExit("Firmware table changed; review RDAB before proceeding.")
    boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    if boot_id != json.loads((captured / "capture.json").read_text())["boot_id"]:
        raise SystemExit("Host rebooted; capture/review its current state first.")
    interface = Path("/sys/kernel/debug/acpi/acpidbg")
    if not interface.exists():
        raise SystemExit("Kernel ACPI debugger unavailable; no hardware access performed.")
    output = root / "reports" / datetime.datetime.now().strftime("host_gpp_%Y%m%d_%H%M%S")
    output.mkdir()
    result = {"boot_id": boot_id, "dsdt_sha256": hashlib.sha256(actual).hexdigest(),
              "configuration_writes": False, "reads": []}
    # Addresses follow this DSDT's CABR/RDAB and AMD's published SB900 GPP code.
    registers = [("ABCFG_GPP_ENABLE", 0xC00000C0),
                 ("ABCFG_POWER", 0xC0000090),
                 ("RCINDXC_POWER", 0x20000065),
                 ("RCINDXC_CLOCK", 0x20000040)]
    for port in range(4):
        registers.append((f"PORT{port}_LTSSM_HISTORY", 0x600000A5 | (port << 24)))
    try:
        for name, address in registers:
            command = f"evaluate \\RDAB 0x{address:08X}"
            print(f"READ {name}: {command}", flush=True)
            run = subprocess.run(["acpidbg", "-b", command], capture_output=True,
                                 text=True, timeout=20)
            text = run.stdout + run.stderr
            (output / f"{name}.txt").write_text(text)
            print(text, flush=True)
            # ACPICA formats an evaluated ACPI integer as '[Integer] = ...'.
            match = re.search(r"\[Integer\]\s*=\s*(?:0x)?([0-9A-Fa-f]+)", text)
            entry = {"name": name, "address": f"0x{address:08X}",
                     "command": command, "exit_code": run.returncode,
                     "value": int(match.group(1), 16) if match else None}
            result["reads"].append(entry)
            if run.returncode or not match:
                raise RuntimeError(f"Cannot verify {name} read; stopping.")
        result["status"] = "capture_pass"
        print("HOST_GPP_CAPTURE_PASS:", output)
    finally:
        (output / "capture.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
