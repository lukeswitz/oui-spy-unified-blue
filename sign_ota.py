#!/usr/bin/env python3
import argparse
import base64
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MAGIC = b"OSG1"
SIG_LEN = 64
TRAILER_LEN = len(MAGIC) + SIG_LEN
APP_MAGIC = 0xE9
DEFAULT_KEY = Path.home() / ".config" / "oui-spy" / "ota_signing_key.pem"
PUBKEY_HEADER = Path(__file__).resolve().parent / "src" / "ota_pubkey.h"
SPKI_PREFIX = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
NOT_APP_SUFFIXES = ("-bootloader.bin", "-partitions.bin", "-boot_app0.bin")


def openssl(*args, data=None):
    return subprocess.run(["openssl", *args], input=data, capture_output=True, check=True).stdout


def der_len(buf, i):
    n = buf[i]
    i += 1
    if n < 0x80:
        return n, i
    count = n & 0x7F
    return int.from_bytes(buf[i:i + count], "big"), i + count


def der_to_rs(der):
    if der[0] != 0x30:
        raise ValueError("signature is not a DER sequence")
    _, i = der_len(der, 1)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("signature value is not a DER integer")
        n, i = der_len(der, i + 1)
        value = int.from_bytes(der[i:i + n], "big")
        out += value.to_bytes(SIG_LEN // 2, "big")
        i += n
    return out


def der_int(value):
    raw = value.lstrip(b"\x00") or b"\x00"
    if raw[0] & 0x80:
        raw = b"\x00" + raw
    return bytes([0x02, len(raw)]) + raw


def rs_to_der(rs):
    body = der_int(rs[:SIG_LEN // 2]) + der_int(rs[SIG_LEN // 2:])
    return bytes([0x30, len(body)]) + body


def key_public_raw(key):
    spki = openssl("ec", "-in", str(key), "-pubout", "-outform", "DER")
    if not spki.startswith(SPKI_PREFIX) or len(spki) != len(SPKI_PREFIX) + 65:
        raise ValueError(f"{key} is not a P-256 key")
    return spki[len(SPKI_PREFIX):]


def header_public_raw():
    raw = bytes(int(h, 16) for h in re.findall(r"0x([0-9a-fA-F]{2})", PUBKEY_HEADER.read_text()))
    if len(raw) != 65 or raw[0] != 0x04:
        raise ValueError(f"{PUBKEY_HEADER} does not hold a 65-byte uncompressed key")
    return raw


def signature_valid(public, image, rs):
    pem = base64.encodebytes(SPKI_PREFIX + public).decode()
    with tempfile.TemporaryDirectory() as tmp:
        pub_path = Path(tmp) / "pub.pem"
        sig_path = Path(tmp) / "sig.der"
        pub_path.write_text(f"-----BEGIN PUBLIC KEY-----\n{pem}-----END PUBLIC KEY-----\n")
        sig_path.write_bytes(rs_to_der(rs))
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", str(pub_path), "-signature", str(sig_path)],
            input=image,
            capture_output=True,
        )
    return result.returncode == 0


def cmd_keygen(args):
    key = Path(args.key).expanduser()
    if key.exists():
        print(f"{key} already exists, not replacing it", file=sys.stderr)
        return 1
    key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    previous = os.umask(0o077)
    try:
        openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key))
    finally:
        os.umask(previous)
    os.chmod(key, 0o600)
    print(f"private key: {key}")
    print("public key: " + key_public_raw(key).hex())
    return 0


def cmd_sign(args):
    key = Path(args.key).expanduser()
    public = key_public_raw(key)
    if public != header_public_raw():
        print(f"{key} does not match {PUBKEY_HEADER}", file=sys.stderr)
        return 1
    rc = 0
    for name in args.files:
        path = Path(name)
        if path.name.endswith(NOT_APP_SUFFIXES):
            print(f"skip {path}: not an app image")
            continue
        image = path.read_bytes()
        if not image or image[0] != APP_MAGIC:
            print(f"refuse {path}: first byte is not 0x{APP_MAGIC:02X}", file=sys.stderr)
            rc = 1
            continue
        if image[-TRAILER_LEN:-SIG_LEN] == MAGIC:
            print(f"refuse {path}: already signed", file=sys.stderr)
            rc = 1
            continue
        rs = der_to_rs(openssl("dgst", "-sha256", "-sign", str(key), data=image))
        if not signature_valid(public, image, rs):
            print(f"refuse {path}: new signature failed verification", file=sys.stderr)
            rc = 1
            continue
        tmp = path.with_name(path.name + ".signing")
        tmp.write_bytes(image + MAGIC + rs)
        os.replace(tmp, path)
        print(f"signed {path}: {len(image)} + {TRAILER_LEN} bytes")
    return rc


def cmd_verify(args):
    public = header_public_raw()
    rc = 0
    for name in args.files:
        path = Path(name)
        if path.name.endswith(NOT_APP_SUFFIXES):
            print(f"skip {path}: not an app image")
            continue
        data = path.read_bytes()
        if len(data) <= TRAILER_LEN or data[-TRAILER_LEN:-SIG_LEN] != MAGIC:
            print(f"UNSIGNED {path}")
            rc = 1
        elif signature_valid(public, data[:-TRAILER_LEN], data[-SIG_LEN:]):
            print(f"OK {path}")
        else:
            print(f"BAD SIGNATURE {path}")
            rc = 1
    return rc


def main():
    parser = argparse.ArgumentParser(description="Sign OUI-SPY firmware images for over-the-air updates.")
    sub = parser.add_subparsers(dest="command", required=True)
    keygen = sub.add_parser("keygen", help="create the private signing key")
    keygen.add_argument("--key", default=str(DEFAULT_KEY))
    keygen.set_defaults(func=cmd_keygen)
    sign = sub.add_parser("sign", help="append a signature to firmware images, in place")
    sign.add_argument("--key", default=str(DEFAULT_KEY))
    sign.add_argument("files", nargs="+")
    sign.set_defaults(func=cmd_sign)
    verify = sub.add_parser("verify", help="check images against the key in src/ota_pubkey.h")
    verify.add_argument("files", nargs="+")
    verify.set_defaults(func=cmd_verify)
    args = parser.parse_args()
    try:
        return args.func(args)
    except subprocess.CalledProcessError as e:
        print(e.stderr.decode(errors="replace"), file=sys.stderr)
        return 1
    except (OSError, ValueError) as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
