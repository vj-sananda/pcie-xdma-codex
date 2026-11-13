#!/usr/bin/env python3
"""Exercise XDMA channel 0 concurrently to avoid a full loopback FIFO deadlock."""
import argparse
import hashlib
import json
import multiprocessing as mp
import mmap
import os
from pathlib import Path
import random
import time


def receiver(device, size, output, result):
    try:
        with mmap.mmap(-1, size) as data:
            with open(device, 'rb', buffering=0) as stream:
                received = 0
                while received < size:
                    with memoryview(data)[received:] as target:
                        count = stream.readinto(target)
                    if not count:
                        raise RuntimeError('Unexpected end of C2H stream')
                    received += count
            Path(output).write_bytes(data)
        result.put(('ok', received))
    except Exception as exc:
        result.put(('error', str(exc)))


def sender(device, payload, result):
    try:
        fd = os.open(device, os.O_WRONLY)
        try:
            # Anonymous mmap provides the page alignment XDMA streaming requires.
            with mmap.mmap(-1, len(payload)) as aligned:
                aligned[:] = payload
                sent = os.write(fd, aligned)
                if sent != len(payload):
                    raise RuntimeError(f'Short H2C transfer: {sent}/{len(payload)}')
        finally:
            os.close(fd)
        result.put(('ok', sent))
    except Exception as exc:
        result.put(('error', str(exc)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='/dev/xdma0')
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('--output', type=Path, default=Path('reports/dma_results.json'))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    records = []
    # Multiples of the 128-bit stream word; test below and above 64 KiB FIFO capacity.
    for size in (16, 4096, 65536, 1048576, 4194304):
        payload = random.Random(0xC7 + size).randbytes(size)
        output = args.output.parent / f'dma_rx_{size}.bin'
        rxq, txq = mp.Queue(), mp.Queue()
        rx = mp.Process(target=receiver, args=(args.prefix + '_c2h_0', size, output, rxq))
        tx = mp.Process(target=sender, args=(args.prefix + '_h2c_0', payload, txq))
        start = time.monotonic()
        rx.start()
        tx.start()
        deadline = start + args.timeout
        for proc in (tx, rx):
            proc.join(max(0, deadline - time.monotonic()))
        if tx.is_alive() or rx.is_alive():
            for proc in (tx, rx):
                if proc.is_alive():
                    proc.kill()
                proc.join(2)
            raise RuntimeError(f'DMA timed out at {size} bytes; inspect driver and PCIe link')
        for q in (txq, rxq):
            status, detail = q.get(timeout=2)
            if status != 'ok':
                raise RuntimeError(detail)
        received = output.read_bytes()
        if received != payload:
            raise RuntimeError(f'DMA data mismatch at {size} bytes')
        elapsed = time.monotonic() - start
        record = dict(bytes=size, seconds=elapsed, sha256=hashlib.sha256(received).hexdigest(), result='PASS')
        records.append(record)
        args.output.write_text(json.dumps(records, indent=2) + '\n')
        print(json.dumps(record), flush=True)
        output.unlink()
    print('DMA_TEST_PASS', flush=True)


if __name__ == '__main__':
    main()
