#!/usr/bin/env python3
"""Laptop side of the live demo (see core0_link.c for the frame format).

    python3 laptop.py --port COM5 show    "HELLO NOC"    # laptop encrypts, the FPGA decrypts and shows it
    python3 laptop.py --port COM5 encrypt "any message"  # the FPGA encrypts, the laptop decrypts and prints

--port is the board's USB serial port (Windows: COMn, macOS: /dev/tty.usbserial-..., Linux:
/dev/ttyUSBn). Needs pyserial (pip install pyserial) and either the `cryptography` package or
the `openssl` command for the laptop's own AES.

`show`: the laptop sends ciphertext only. The plaintext appears on the board's display, so
it was decrypted there. `encrypt`: the laptop sends plaintext and gets ciphertext back,
which it decrypts with its own AES to show the board's answer is right.
"""
import argparse
import hashlib
import struct
import subprocess
import sys

NONCE = 0x00C0FFEE
KEY = hashlib.sha256(b"CooK AES key" + struct.pack("<I", NONCE)).digest()[:16]


def aes(data, decrypt=False):
    """AES-128-ECB on whole blocks, on the laptop."""
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        c = Cipher(algorithms.AES(KEY), modes.ECB())
        op = c.decryptor() if decrypt else c.encryptor()
        return op.update(data) + op.finalize()
    except ImportError:
        cmd = ["openssl", "enc", "-aes-128-ecb", "-nopad", "-K", KEY.hex()] + (["-d"] if decrypt else [])
        return subprocess.run(cmd, input=data, capture_output=True, check=True).stdout


def pad(text):
    data = text.encode("ascii")
    if len(data) > 64:
        sys.exit("message too long: 64 characters at most")
    return data + b" " * (-len(data) % 16 or (16 if not data else 0))


def frame(op, payload):
    return bytes([0xA5, op, len(payload)]) + payload


def exchange(port, request, timeout):
    import serial
    with serial.Serial(port, 115200, timeout=timeout) as s:
        s.reset_input_buffer()
        s.write(request)
        head = s.read(3)
        if len(head) != 3 or head[0] != 0x5A:
            sys.exit(f"no valid reply from the board (got {head.hex() or 'nothing'})")
        body = s.read(head[2])
        if len(body) != head[2]:
            sys.exit("reply cut short")
        return head[1], body


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True)
    ap.add_argument("--timeout", type=float, default=10.0, help="seconds to wait for the board")
    ap.add_argument("mode", choices=["show", "encrypt"])
    ap.add_argument("message")
    a = ap.parse_args()
    plain = pad(a.message)

    if a.mode == "show":
        cipher = aes(plain)
        print(f"sending ciphertext only: {cipher.hex()}")
        status, _ = exchange(a.port, frame(1, cipher), a.timeout)
        if status:
            sys.exit(f"board reported error {status}")
        print(f"board decrypted it; its display should read: {plain[:8].decode()!r}")
    else:
        status, cipher = exchange(a.port, frame(2, plain), a.timeout)
        if status:
            sys.exit(f"board reported error {status}")
        print(f"ciphertext from the board: {cipher.hex()}")
        back = aes(cipher, decrypt=True)
        print(f"decrypted on the laptop:   {back.decode(errors='replace')!r}")
        print("MATCH: the board's AES agrees with the laptop's" if back == plain else "MISMATCH")


if __name__ == "__main__":
    main()
