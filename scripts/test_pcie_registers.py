#!/usr/bin/env python3
"""Test accelerator GPIO and LM73 through the XDMA user BAR on an x86 Linux host."""
import argparse
import ctypes
from datetime import datetime
import json
import mmap
import os
from pathlib import Path
import sys
import time


def check(condition, message):
    if not condition:
        raise RuntimeError(message)
    print(f'PASS: {message}', flush=True)


class Registers:
    def __init__(self, mapping):
        self.mapping = mapping

    def read(self, offset):
        # A native aligned 32-bit access, rather than bytewise MMIO copies.
        return ctypes.c_uint32.from_buffer(self.mapping, offset).value

    def write(self, offset, value):
        ctypes.c_uint32.from_buffer(self.mapping, offset).value = value
        self.read(8)  # Read completion drains posted PCIe writes.

    def sensor_read(self, address, register):
        base = 0x10000
        self.write(base + 0x40, 0xA)
        self.write(base + 0x120, 0xF)
        for value in (0x100 | address << 1, register,
                      0x101 | address << 1, 0x202):
            self.write(base + 0x108, value)
        self.write(base + 0x100, 1)
        data = []
        deadline = time.monotonic() + 0.25
        while len(data) < 2 and time.monotonic() < deadline:
            if not self.read(base + 0x104) & 0x40:
                data.append(self.read(base + 0x10C) & 0xFF)
            else:
                time.sleep(0.001)
        if len(data) != 2:
            raise RuntimeError(f'LM73 read timed out at address 0x{address:02X}')
        return data[0] << 8 | data[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', type=Path, default=Path('/dev/xdma0_user'))
    parser.add_argument('--output', type=Path,
                        default=Path('reports/pcie_register_results.json'))
    args = parser.parse_args()
    if sys.byteorder != 'little' or os.uname().machine not in ('x86_64', 'i686'):
        raise RuntimeError('This MMIO test requires a little-endian x86 host')
    pci = (Path('/sys/class/xdma') / args.device.name / 'device').resolve(strict=True)
    check((pci / 'vendor').read_text().strip() == '0x10ee'
          and (pci / 'device').read_text().strip() == '0x7021',
          f'expected PCIe endpoint 10ee:7021 at {pci.name}')
    results = dict(timestamp=datetime.now().astimezone().isoformat(),
                   device=str(args.device), pci_address=pci.name,
                   link_speed=(pci / 'current_link_speed').read_text().strip(),
                   link_width=int((pci / 'current_link_width').read_text()))
    with args.device.open('r+b', buffering=0) as device:
        with mmap.mmap(device.fileno(), 0x20000, flags=mmap.MAP_SHARED,
                       prot=mmap.PROT_READ | mmap.PROT_WRITE) as mapping:
            regs = Registers(mapping)
            initial = regs.read(8)
            check(initial >> 24 == 0xC7, 'design signature C7 before register writes')
            check(initial & 7 == 7, 'PCIe link up, PERST# and DMA reset released')
            time.sleep(0.1)
            later = regs.read(8)
            check((initial ^ later) & 0x00FFFFC0, 'independent clock counter advances')
            results['status_before'] = f'{initial:08X}'
            patterns = (0, 1, 2, 4, 7, 5, 2, 0)
            original_leds = regs.read(0) & 7
            try:
                for pattern in patterns:
                    regs.write(0, pattern)
                    time.sleep(0.01)
                    check(regs.read(8) >> 3 & 7 == pattern,
                          f'LED register pattern {pattern} through PCIe')
            finally:
                regs.write(0, original_leds)
            results['led_patterns'] = list(patterns)
            # Board address established by the preceding JTAG identification test.
            sensor_id = regs.sensor_read(0x4A, 7)
            check(sensor_id == 0x0190, 'LM73 address=0x4A identification=0x0190')
            results['lm73_address'] = '0x4A'
            results['lm73_identification'] = f'0x{sensor_id:04X}'
            results['temperatures_celsius'] = []
            for sample in range(3):
                raw = regs.sensor_read(0x4A, 0)
                temperature = (raw - 65536 if raw >= 32768 else raw) / 128.0
                check(-40 <= temperature <= 125, 'temperature in LM73 operating range')
                print(f'TEMPERATURE: sample={sample} raw={raw:04X} celsius={temperature:.3f}')
                results['temperatures_celsius'].append(temperature)
                time.sleep(0.1)
            check(regs.read(8) & 7 == 7, 'PCIe link and reset state remain healthy')
    results['result'] = 'PASS'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    print('PCIE_REGISTERS_PASS', flush=True)


if __name__ == '__main__':
    main()
