#!/usr/bin/env python3
"""
uart_host.py -- PC side of the hardware test on the DE2-115

Sends random signed INT8 matrices A and B to the board over the serial
port, reads back C = A x B (16 x INT32, little-endian), and checks every
value against a reference computed on the PC. This is the same check the
simulation testbench does, but on the real FPGA.

Setup:
    pip install pyserial
    Connect the DE2-115 RS-232 port to the PC (RS-232-to-USB adapter),
    program the board with output_files/matmul_uart_top.sof, then flip SW17
    up and back down to reset (3DQ5 convention).

Usage:
    python3 scripts/uart_host.py --port COM3 --count 1000 --seed 1
    python3 scripts/uart_host.py --port /dev/ttyUSB0 --count 10 --show
    python3 scripts/uart_host.py --selftest     # check this script offline
"""

import argparse
import random
import struct
import sys
import time

N = 4


def reference(a, b):
    """Plain nested-loop matrix multiply (row-major lists of length 16)."""
    return [sum(a[i * N + k] * b[k * N + j] for k in range(N))
            for i in range(N) for j in range(N)]


def pack_request(a, b):
    """32 bytes: A then B, row-major, each value as a signed byte."""
    return struct.pack("<32b", *(a + b))


def unpack_reply(data):
    """64 bytes -> 16 signed 32-bit little-endian integers."""
    return list(struct.unpack("<16i", data))


def random_matrix(rng):
    corners = [-128, 127, 0, -1, 1]
    return [rng.choice(corners) if rng.random() < 0.2 else rng.randint(-128, 127)
            for _ in range(N * N)]


def show(name, m):
    print(f"{name} =")
    for i in range(N):
        print("   " + " ".join(f"{v:7d}" for v in m[i * N:(i + 1) * N]))


class FakeBoard:
    """Offline stand-in for the FPGA, used by --selftest."""

    def __init__(self):
        self.out = b""

    def write(self, data):
        vals = list(struct.unpack("<32b", data))
        self.out = struct.pack("<16i", *reference(vals[:16], vals[16:]))

    def read(self, n):
        data, self.out = self.out[:n], self.out[n:]
        return data

    def reset_input_buffer(self):
        pass

    def close(self):
        pass


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", help="serial port, e.g. COM3 or /dev/ttyUSB0")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--count", type=int, default=100, help="number of matrix pairs")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--show", action="store_true", help="print each A, B, C")
    p.add_argument("--selftest", action="store_true", help="run against a fake board")
    a = p.parse_args()

    if a.selftest:
        port = FakeBoard()
    else:
        if not a.port:
            p.error("--port is required (or use --selftest)")
        import serial  # pyserial
        port = serial.Serial(a.port, a.baud, timeout=2)
        time.sleep(0.2)
        port.reset_input_buffer()

    rng = random.Random(a.seed)
    mismatches = 0
    t0 = time.time()
    for n in range(a.count):
        A, B = random_matrix(rng), random_matrix(rng)
        port.write(pack_request(A, B))
        reply = port.read(64)
        if len(reply) != 64:
            print(f"matrix {n}: timeout, got {len(reply)} of 64 bytes "
                  f"(flip SW17 up and down on the board to resync)")
            port.close()
            return 1
        C = unpack_reply(reply)
        expected = reference(A, B)
        bad = [i for i in range(N * N) if C[i] != expected[i]]
        if a.show:
            show("A", A); show("B", B); show("C (FPGA)", C)
        if bad:
            mismatches += len(bad)
            for i in bad[:4]:
                print(f"matrix {n}: C[{i // N}][{i % N}] expected {expected[i]}, got {C[i]}")
    port.close()

    dt = time.time() - t0
    print("-" * 50)
    print(f"Matrices checked : {a.count}   ({a.count * 16} outputs)")
    print(f"Mismatches       : {mismatches}")
    print(f"Time             : {dt:.2f} s")
    print("HARDWARE TEST PASSED" if mismatches == 0 else "HARDWARE TEST FAILED")
    return 0 if mismatches == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
