#!/usr/bin/env python3
# detector.py
#
# Cross-view diff between /proc/modules and /sys/module/.
# Diamorphine hooks getdents64 to hide from procfs.
# It doesn't touch kernfs — so the module still shows up under /sys/module/.
# That gap is what we exploit.
#
# Requires root. Run with: sudo python3 detector.py

import argparse
import json
import os
import sys
import time
from datetime import datetime

if sys.stdout.isatty():
    RED    = "\033[31m"
    GREEN  = "\033[32m"
    YELLOW = "\033[33m"
    GRAY   = "\033[90m"
    BOLD   = "\033[1m"
    RST    = "\033[0m"
else:
    RED = GREEN = YELLOW = GRAY = BOLD = RST = ""


def read_proc():
    """Names from /proc/modules — the path diamorphine hooks."""
    try:
        with open("/proc/modules") as f:
            return {line.split()[0] for line in f if line.strip()}
    except PermissionError:
        bail("can't read /proc/modules — are you root?")
    except FileNotFoundError:
        bail("/proc/modules not found")


def read_sysfs():
    """
    Names from /sys/module/ that have an initstate file.
    Built-in kernel objects live here too but never have initstate.
    Loadable modules — including hidden ones — always do.
    Diamorphine doesn't hook this path at all.
    """
    try:
        entries = os.listdir("/sys/module")
    except PermissionError:
        bail("can't read /sys/module — are you root?")
    except FileNotFoundError:
        bail("/sys/module not found — is sysfs mounted?")

    out = set()
    for name in entries:
        if os.path.exists(f"/sys/module/{name}/initstate"):
            out.add(name)
    return out


def bail(msg):
    print(f"fatal: {msg}", file=sys.stderr)
    sys.exit(1)


def kernel_version():
    try:
        return open("/proc/version").read().split()[2]
    except Exception:
        return "unknown"


def module_size(name):
    try:
        with open("/proc/modules") as f:
            for line in f:
                parts = line.split()
                if parts[0] == name and len(parts) >= 2:
                    sz = int(parts[1])
                    return f"{sz // 1024} kB" if sz >= 1024 else f"{sz} B"
    except Exception:
        pass
    return "unknown"


def module_initstate(name):
    try:
        return open(f"/sys/module/{name}/initstate").read().strip()
    except Exception:
        return "unknown"


def module_holders(name):
    try:
        h = os.listdir(f"/sys/module/{name}/holders")
        return ", ".join(h) if h else "none"
    except Exception:
        return "none"


def print_summary(proc, sysfs, ts):
    hidden    = sorted(sysfs - proc)
    proc_only = sorted(proc - sysfs)
    common    = proc & sysfs

    print(f"\n{GRAY}{ts}  kernel {kernel_version()}{RST}")
    print(f"{GRAY}proc_modules={len(proc)}  sysfs_modules={len(sysfs)}  "
          f"delta={len(hidden)}{RST}\n")

    if hidden:
        print(f"{RED}{BOLD}hidden modules detected{RST}  "
              f"({len(hidden)} found in sysfs, absent from procfs)\n")
        for name in hidden:
            print(f"  {RED}{BOLD}{name}{RST}")
            print(f"    {GRAY}initstate : {RST}{module_initstate(name)}")
            print(f"    {GRAY}holders   : {RST}{module_holders(name)}")
            print(f"    {GRAY}sysfs     : {RST}/sys/module/{name}/")
            print(f"    {GRAY}procfs    : {RST}{RED}absent — filtered by hook{RST}")
            print()
        print(f"{RED}{BOLD}verdict: System Compromised{RST}")
        print(f"{GRAY}to unhide: sudo kill -63 0{RST}")
        print(f"{GRAY}to remove: sudo rmmod {hidden[0]}{RST}\n")
    else:
        print(f"{GREEN}verdict: Clean{RST}")
        print(f"{GRAY}proc and sysfs agree on {len(common)} loaded modules{RST}\n")

    if proc_only:
        print(f"{YELLOW}anomalies — in procfs but not sysfs ({len(proc_only)}){RST}")
        for name in proc_only:
            print(f"  {YELLOW}{name}{RST}  {GRAY}size={module_size(name)}{RST}")
        print()

    return hidden


def print_json_out(proc, sysfs):
    hidden    = sorted(sysfs - proc)
    proc_only = sorted(proc - sysfs)
    result = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "kernel":    kernel_version(),
        "verdict":   "Compromised" if hidden else "CLEAN",
        "proc_module_count":  len(proc),
        "sysfs_module_count": len(sysfs),
        "hidden_modules": [
            {
                "name":       name,
                "initstate":  module_initstate(name),
                "holders":    module_holders(name),
                "sysfs_path": f"/sys/module/{name}/",
            }
            for name in hidden
        ],
        "proc_only_modules": proc_only,
    }
    print(json.dumps(result, indent=2))
    return hidden


def watch(interval, quiet):
    last_verdict = None
    print(f"watching for hidden modules  (interval={interval}s  ctrl-c to stop)\n")

    while True:
        try:
            proc   = read_proc()
            sysfs  = read_sysfs()
            hidden = sorted(sysfs - proc)
            verdict = bool(hidden)
            ts = datetime.now().strftime("%H:%M:%S")

            if verdict != last_verdict:
                os.system("clear")
                print(f"watching for hidden modules  "
                      f"(interval={interval}s  ctrl-c to stop)\n")
                if verdict and last_verdict is not None:
                    print(f"{RED}{BOLD}[{ts}] rootkit appeared{RST}\n")
                elif not verdict and last_verdict is not None:
                    print(f"{GREEN}{BOLD}[{ts}] system clean{RST}\n")

                if not quiet:
                    print_summary(proc, sysfs, ts)
                else:
                    if hidden:
                        for name in hidden:
                            print(f"{RED}[hidden]{RST}  {name}  "
                                  f"initstate={module_initstate(name)}")
                        print(f"\n{RED}{BOLD}SYSTEM COMPROMISED{RST}\n")
                    else:
                        print(f"{GREEN}CLEAN{RST}\n")

                last_verdict = verdict
            else:
                tag = (f"{RED}COMPROMISED  {', '.join(hidden)}{RST}"
                       if verdict else f"{GREEN}clean{RST}")
                sys.stdout.write(f"\r[{ts}]  {tag}   ")
                sys.stdout.flush()

            time.sleep(interval)

        except KeyboardInterrupt:
            print("\nstopped")
            sys.exit(0)


def main():
    ap = argparse.ArgumentParser(
        description="cross-view LKM rootkit detector",
        epilog="compares /proc/modules vs /sys/module/ to find hidden kernel modules"
    )
    ap.add_argument("--watch",    action="store_true",
                    help="poll continuously, react on state changes")
    ap.add_argument("--interval", type=float, default=2.0, metavar="SEC",
                    help="poll interval for --watch (default: 2)")
    ap.add_argument("--quiet",    action="store_true",
                    help="less output")
    ap.add_argument("--json",     action="store_true",
                    help="machine-readable output (single scan only)")
    args = ap.parse_args()

    if os.geteuid() != 0:
        print("warning: not root — results may be incomplete", file=sys.stderr)

    if args.watch and args.json:
        bail("--watch and --json are mutually exclusive")

    if args.watch:
        watch(args.interval, args.quiet)
        return

    proc  = read_proc()
    sysfs = read_sysfs()
    ts    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if args.json:
        hidden = print_json_out(proc, sysfs)
    else:
        hidden = print_summary(proc, sysfs, ts)

    sys.exit(1 if hidden else 0)


if __name__ == "__main__":
    main()
