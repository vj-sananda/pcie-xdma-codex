#!/usr/bin/env python3
"""Validate the completed flash backup and exact BPI image, then record hashes."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bit_payload(path):
    data = path.read_bytes()
    offset = 2 + int.from_bytes(data[:2], "big")
    require(data[offset:offset + 2] == b"\0\1", "Invalid bitstream header")
    offset += 2
    for expected in b"abcde":
        require(data[offset] == expected, "Unexpected bitstream field")
        offset += 1
        size_bytes = 4 if expected == ord("e") else 2
        size = int.from_bytes(data[offset:offset + size_bytes], "big")
        offset += size_bytes
        value = data[offset:offset + size]
        require(len(value) == size, "Truncated bitstream")
        offset += size
        if expected == ord("e"):
            require(offset == len(data), "Unexpected data after bitstream payload")
            return value


def mcs_payload(path):
    payload = bytearray()
    base, ended = 0, False
    for line in path.read_text().splitlines():
        require(line.startswith(":"), "Invalid Intel HEX line")
        raw = bytes.fromhex(line[1:])
        require(len(raw) >= 5 and len(raw) == raw[0] + 5 and sum(raw) % 256 == 0,
                "Invalid Intel HEX length or checksum")
        require(not ended, "Data after Intel HEX end record")
        kind, address, body = raw[3], int.from_bytes(raw[1:3], "big"), raw[4:-1]
        if kind == 0:
            require(base + address == len(payload), "Image is not contiguous from address zero")
            payload.extend(body)
        elif kind == 4:
            require(len(body) == 2 and address == 0, "Invalid extended address record")
            base = int.from_bytes(body, "big") << 16
        elif kind == 1:
            require(not body and address == 0, "Invalid end record")
            ended = True
        else:
            raise ValueError(f"Unsupported Intel HEX record type {kind}")
    require(ended, "Missing Intel HEX end record")
    return bytes(payload)


def main():
    log = (ROOT / "reports/backup_flash.log").read_text()
    match = re.search(r"^FLASH_BACKUP_PASS: (.+) bytes=67108864 repeated_header=match$", log, re.M)
    require(match and "\nSRAM_RESTORE_PASS:" in log, "Backup and SRAM restoration must both finish")
    backup = Path(match.group(1)).resolve()
    require(backup.parent == ROOT / "backups", "Backup is outside the backup directory")
    original = backup.read_bytes()
    require(len(original) == 64 * 1024 * 1024, "Backup is not the full 64 MiB")
    sample = backup.with_name(backup.name.replace("flash_before_", "flash_sample_"))
    require(sample.read_bytes() == original[:4096], "Independent header read does not match")
    bit = ROOT / "build/accelerator_boot.bit"
    mcs = ROOT / "build/accelerator_boot.mcs"
    payload = mcs_payload(mcs)
    require(0 < len(payload) <= len(original), "Image does not fit flash")
    # BPI x16 mirrors bits within each byte, then swaps bytes within each word.
    mirror = bytes(int(f"{x:08b}"[::-1], 2) for x in range(256))
    converted = bit_payload(bit).translate(mirror)
    require(len(converted) % 2 == 0, "BPI payload must contain complete 16-bit words")
    expected = bytearray(converted)
    expected[0::2], expected[1::2] = converted[1::2], converted[0::2]
    require(payload == expected, "MCS does not exactly encode the boot bitstream as BPI x16")
    files = [backup, sample, bit, mcs, ROOT / "scripts/prepare_flash.tcl"]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (ROOT / "reports/flash_artifacts.sha256").write_text(
        "".join(f"{digest}  {name}\n" for name, digest in hashes.items()))
    (ROOT / "backups/verified_backup.txt").write_text(str(backup) + "\n")
    record = {
        "backup": str(backup.relative_to(ROOT)), "backup_bytes": len(original),
        "backup_non_erased_bytes": len(original) - original.count(255),
        "repeated_header_bytes": 4096, "format": "Intel HEX / BPIx16",
        "start_address": "0x00000000", "last_address": f"0x{len(payload)-1:08x}",
        "payload_bytes": len(payload), "exact_bitstream_encoding_verified": True,
        "sha256": hashes, "status": "Prepared; flash write not performed by this script"
    }
    (ROOT / "reports/flash_artifacts.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"FLASH_ARTIFACTS_PASS: backup={backup.name} payload_bytes={len(payload)}")


if __name__ == "__main__":
    main()
