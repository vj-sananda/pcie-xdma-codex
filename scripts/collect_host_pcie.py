#!/usr/bin/env python3
"""Collect PCIe and ACPI evidence; no device, firmware, or kernel settings change."""
import datetime
import json
import os
from pathlib import Path
import subprocess


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run this evidence collector with sudo.")
    root = Path(__file__).resolve().parents[1]
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    output = root / "reports" / ("host_pcie_" + stamp)
    output.mkdir()
    result = {
        "captured_at": datetime.datetime.now().astimezone().isoformat(),
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "commands": [],
    }
    commands = [
        ("lspci_verbose.txt", ["lspci", "-Dnnvv"]),
        ("lspci_tree.txt", ["lspci", "-Dtv"]),
        ("smbus_config.txt", ["lspci", "-s", "0000:00:14.0", "-xxx"]),
        ("dmi_slots.txt", ["dmidecode", "--type", "slot"]),
        ("kernel_log.txt", ["dmesg", "--color=never"]),
    ]
    for filename, command in commands:
        run = subprocess.run(command, capture_output=True, text=True, timeout=30)
        (output / filename).write_text(run.stdout + run.stderr)
        result["commands"].append({"argv": command, "exit_code": run.returncode})
    acpi = output / "acpi"
    acpi.mkdir()
    for table in Path("/sys/firmware/acpi/tables").iterdir():
        if table.is_file() and (table.name == "DSDT" or table.name.startswith("SSDT")):
            (acpi / (table.name + ".aml")).write_bytes(table.read_bytes())
    (output / "capture.json").write_text(json.dumps(result, indent=2) + "\n")
    print("HOST_PCIE_CAPTURE_PASS:", output)


if __name__ == "__main__":
    main()
