#!/usr/bin/env python3
"""
regress.py -- Seeded regression runner for the 4x4 systolic array

Compiles the design + testbench once, then runs it once per seed and
parses each log for "TEST PASSED" / "TEST FAILED". Prints a summary,
writes per-seed logs, and lists the exact command to reproduce any
failing seed.

Examples (run from the project root):
    python3 scripts/regress.py --sim modelsim  --seeds 50
    python3 scripts/regress.py --sim verilator --seeds 200 --num 500
    python3 scripts/regress.py --sim iverilog  --seeds 20 --inject-bug
    python3 scripts/regress.py --sim modelsim  --tb top --seeds 10
    python3 scripts/regress.py --sim iverilog  --tb pe  --seeds 20

--sim modelsim uses vlog/vsim from the Questa/ModelSim Intel FPGA edition
(the same tools as the 3DQ5 labs). verilator and iverilog are free
alternatives.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RTL_CORE = ["rtl/PE.sv", "rtl/systolic_array.sv", "rtl/matmul_core.sv"]
RTL_TOP = RTL_CORE + ["rtl/UART_receiver.sv", "rtl/UART_transmitter.sv", "rtl/PB_controller.sv",
                      "rtl/convert_hex_to_seven_segment.sv", "rtl/matmul_uart_top.sv"]

RTL_INC = os.path.join(ROOT, "rtl")      # for `include "define_state.h"

BENCHES = {
    # name: (top module, testbench file, rtl list, count plusarg)
    "pe": ("TB_PE", "tb/tb_pe.sv", ["rtl/PE.sv"], "NUM_RANDOM"),
    "core": ("TB", "tb/tb_matmul_core.sv", RTL_CORE, "NUM_RANDOM"),
    "top": ("TB_TOP", "tb/tb_top_uart.sv", RTL_TOP, "NUM_MATRICES"),
}


def sh(cmd, cwd, log=None):
    """Run a command, return (exit code, combined output)."""
    res = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True)
    if log:
        with open(log, "w") as f:
            f.write(res.stdout)
    return res.returncode, res.stdout


def build(sim, bench, build_dir, inject_bug):
    top, tb, rtl, _ = BENCHES[bench]
    srcs = [os.path.join(ROOT, f) for f in rtl + [tb]]
    defines = ["INJECT_BUG"] if inject_bug else []
    os.makedirs(build_dir, exist_ok=True)

    if sim == "modelsim":
        sh(["vlib", "work"], build_dir)
        cmd = ["vlog", "-sv", "-work", "work", f"+incdir+{RTL_INC}"]
        cmd += [f"+define+{d}" for d in defines] + srcs
        code, out = sh(cmd, build_dir, os.path.join(build_dir, "compile.log"))
        return code == 0 and "Error" not in out, out
    if sim == "verilator":
        cmd = ["verilator", "--binary", "--timing", "-j", "0", "-O1",
               "-Wno-fatal", "-Wno-WIDTH", "-Wno-UNSIGNED", "--top-module", top, "-Mdir", build_dir, "-o", "simv",
               f"-I{RTL_INC}"]
        cmd += [f"-D{d}" for d in defines] + srcs
        code, out = sh(cmd, ROOT, os.path.join(build_dir, "compile.log"))
        return code == 0, out
    if sim == "iverilog":
        cmd = ["iverilog", "-g2012", "-s", top, "-I", RTL_INC,
               "-o", os.path.join(build_dir, "simv.vvp")]
        cmd += [f"-D{d}" for d in defines] + srcs
        code, out = sh(cmd, ROOT, os.path.join(build_dir, "compile.log"))
        return code == 0, out
    raise ValueError(sim)


def run_cmd(sim, bench, build_dir, seed, num):
    top, _, _, count_arg = BENCHES[bench]
    args = [f"+SEED={seed}", f"+{count_arg}={num}"]
    if sim == "modelsim":
        return ["vsim", "-c", "-lib", "work", top] + args + ["-do", "run -all; quit -f"]
    if sim == "verilator":
        return [os.path.join(build_dir, "simv")] + args
    return ["vvp", "-n", os.path.join(build_dir, "simv.vvp")] + args


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--sim", choices=["modelsim", "verilator", "iverilog"], default="modelsim")
    p.add_argument("--tb", choices=list(BENCHES), default="core")
    p.add_argument("--seeds", type=int, default=20, help="number of seeds to run")
    p.add_argument("--first-seed", type=int, default=1)
    p.add_argument("--num", type=int, default=None,
                   help="random tests per seed (default 2000 pe / 500 core / 20 top)")
    p.add_argument("--inject-bug", action="store_true",
                   help="compile with +define+INJECT_BUG to prove the bench catches bugs")
    a = p.parse_args()

    num = a.num if a.num is not None else {"pe": 2000, "core": 500, "top": 20}[a.tb]
    tag = f"{a.sim}_{a.tb}{'_bug' if a.inject_bug else ''}"
    build_dir = os.path.join(ROOT, "sim", "regress", tag)
    log_dir = os.path.join(build_dir, "logs")
    if os.path.isdir(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(log_dir)

    print(f"Building {a.tb} bench with {a.sim}{' (INJECT_BUG)' if a.inject_bug else ''} ...")
    ok, out = build(a.sim, a.tb, build_dir, a.inject_bug)
    if not ok:
        print(out)
        print("BUILD FAILED")
        return 2

    passed, failed = [], []
    t0 = time.time()
    for seed in range(a.first_seed, a.first_seed + a.seeds):
        cmd = run_cmd(a.sim, a.tb, build_dir, seed, num)
        _, out = sh(cmd, build_dir, os.path.join(log_dir, f"seed_{seed}.log"))
        if "TEST PASSED" in out:
            passed.append(seed)
            status = "PASS"
        else:
            failed.append(seed)
            status = "FAIL"
        print(f"  seed {seed:5d}: {status}")

    elapsed = time.time() - t0
    print("-" * 50)
    print(f"Bench      : {a.tb}   Simulator: {a.sim}   Tests per seed: {num}")
    print(f"Seeds run  : {len(passed) + len(failed)}   Passed: {len(passed)}   Failed: {len(failed)}")
    print(f"Run time   : {elapsed:.1f} s")
    print(f"Logs       : {os.path.relpath(log_dir, ROOT)}/")
    if failed:
        s = failed[0]
        print(f"First failing seed: {s}  ->  reproduce with:")
        print("  " + " ".join(run_cmd(a.sim, a.tb, build_dir, s, num)))
        print("REGRESSION FAILED")
        return 1
    print("REGRESSION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
