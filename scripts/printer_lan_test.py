#!/usr/bin/env python3
"""LAN smoke test for HS-802UL (port 9100) — run from Mac on same Wi‑Fi as printer.

Usage:
  python3 scripts/printer_lan_test.py 192.168.1.100
  python3 scripts/printer_lan_test.py 192.168.1.100 --drawer
  python3 scripts/printer_lan_test.py 192.168.1.100 --drawer5
"""

from __future__ import annotations

import argparse
import socket
import sys
from datetime import datetime

INIT = bytes([0x1B, 0x40])
CUT = bytes([0x1D, 0x56, 0x00])
DRAWER_PIN2 = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])
DRAWER_PIN5 = bytes([0x1B, 0x70, 0x01, 0x19, 0xFA])


def send(host: str, port: int, payload: bytes) -> None:
    with socket.create_connection((host, port), timeout=4) as sock:
        sock.sendall(payload)


def test_print(host: str, port: int) -> None:
    body = "\n".join(
        [
            "CoffeeSpot",
            "Printer LAN test",
            f"Host: {host}",
            datetime.now().isoformat(timespec="seconds"),
            "----------------",
            "If you can read this,",
            "network print works.",
            "",
            "",
            "",
        ]
    ).encode("ascii", errors="replace")
    send(host, port, INIT + body + CUT)


def main() -> int:
    parser = argparse.ArgumentParser(description="CoffeeSpot printer/kaha LAN smoke test")
    parser.add_argument("host", help="Printer IP, e.g. 192.168.1.100")
    parser.add_argument("--port", type=int, default=9100)
    parser.add_argument("--drawer", action="store_true", help="Kick drawer pin 2")
    parser.add_argument("--drawer5", action="store_true", help="Kick drawer pin 5")
    args = parser.parse_args()

    try:
        if args.drawer or args.drawer5:
            kick = DRAWER_PIN5 if args.drawer5 else DRAWER_PIN2
            send(args.host, args.port, kick)
            print(f"OK drawer kick → {args.host}:{args.port}")
        else:
            test_print(args.host, args.port)
            print(f"OK test print → {args.host}:{args.port}")
        return 0
    except OSError as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
