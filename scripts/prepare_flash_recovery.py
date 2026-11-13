#!/usr/bin/env python3
"""Prepare the original first 4 MiB from this board's verified raw flash backup."""
import hashlib
import json
from pathlib import Path

from record_flash_artifacts import mcs_payload, require

ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / 'backups/flash_before_20261111_195055.bin'
BACKUP_SHA256 = '9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90'
RESTORE_BYTES = 4 * 1024 * 1024  # 16 complete 256 KiB erase blocks.


def record(address, kind, data):
    raw = bytes([len(data)]) + address.to_bytes(2, 'big') + bytes([kind]) + data
    return ':' + (raw + bytes([-sum(raw) & 255])).hex().upper() + '\n'


def main():
    original = BACKUP.read_bytes()
    require(len(original) == 64 * 1024 * 1024, 'Backup must contain all 64 MiB')
    require(hashlib.sha256(original).hexdigest() == BACKUP_SHA256, 'Original backup hash mismatch')
    sample = ROOT / 'backups/flash_sample_20261111_195055.bin'
    require(sample.read_bytes() == original[:4096], 'Independent backup header mismatch')
    data = original[:RESTORE_BYTES]
    image = ROOT / 'build/restore_original_boot_blocks.mcs'
    temporary = image.with_suffix('.mcs.tmp')
    # The backup already contains raw memory bytes. Do NOT apply bitstream
    # bit mirroring or word-byte swapping a second time.
    with temporary.open('w') as output:
        for base in range(0, len(data), 65536):
            output.write(record(0, 4, (base >> 16).to_bytes(2, 'big')))
            for offset in range(base, base + 65536, 16):
                output.write(record(offset & 65535, 0, data[offset:offset + 16]))
        output.write(record(0, 1, b''))
    require(mcs_payload(temporary) == data, 'Recovery MCS differs from raw backup bytes')
    temporary.replace(image)
    files = [BACKUP, sample, image, Path(__file__).resolve(), ROOT / 'scripts/restore_flash.tcl']
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (ROOT / 'reports/flash_recovery.sha256').write_text(
        ''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
    result = dict(backup=str(BACKUP.relative_to(ROOT)), backup_sha256=BACKUP_SHA256,
                  image=str(image.relative_to(ROOT)), start_address='0x00000000',
                  last_address='0x003fffff', bytes=RESTORE_BYTES,
                  exact_raw_backup_bytes_verified=True, sha256=hashes,
                  status='Prepared locally; no hardware access or flash write')
    (ROOT / 'reports/flash_recovery.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'FLASH_RECOVERY_IMAGE_PASS: {image} bytes={len(data)}')


if __name__ == '__main__':
    main()
