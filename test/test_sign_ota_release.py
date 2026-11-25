# Copyright (c) 2026 Luke Switzer
import contextlib
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import sign_ota  # noqa: E402


def make_key(directory, name):
    key = directory / name
    sign_ota.openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key))
    return key


def write_header(directory, key):
    public = sign_ota.key_public_raw(key)
    rows = ", ".join(f"0x{b:02x}" for b in public)
    path = directory / "ota_pubkey.h"
    path.write_text(f"static const uint8_t OTA_SIG_PUBKEY[65] = {{ {rows} }};\n")
    return path


class ReleaseManifestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.key = make_key(self.dir, "throwaway.pem")
        self.header = write_header(self.dir, self.key)
        self.saved_header = sign_ota.PUBKEY_HEADER
        sign_ota.PUBKEY_HEADER = self.header
        self.apk = self.dir / "oui-spy-v9.9.9.apk"
        self.apk.write_bytes(b"apk bytes")
        self.zip = self.dir / "oui-spy-macos-v9.9.9.zip"
        self.zip.write_bytes(b"zip bytes" * 100)
        self.out = self.dir / "out"

    def tearDown(self):
        sign_ota.PUBKEY_HEADER = self.saved_header
        self.tmp.cleanup()

    def run_cli(self, *argv):
        saved = sys.argv
        sys.argv = ["sign_ota.py", *argv]
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                rc = sign_ota.main()
        finally:
            sys.argv = saved
        return rc, buf.getvalue()

    def release(self, *extra):
        return self.run_cli(
            "release", "--key", str(self.key), "--version", "9.9.9", "--build", "3",
            "--out", str(self.out), *extra, str(self.apk), str(self.zip),
        )

    def test_writes_manifest_and_signature(self):
        rc, text = self.release()
        self.assertEqual(rc, 0, text)
        manifest = json.loads((self.out / "release.json").read_text())
        self.assertEqual(manifest["format"], 1)
        self.assertEqual(manifest["app"], "oui-spy")
        self.assertEqual(manifest["version"], "9.9.9")
        self.assertEqual(manifest["build"], 3)
        self.assertEqual(manifest["tag"], "v9.9.9")
        names = {f["name"]: f for f in manifest["files"]}
        self.assertEqual(names[self.apk.name]["size"], 9)
        self.assertEqual(names[self.apk.name]["sha256"], hashlib.sha256(b"apk bytes").hexdigest())
        self.assertEqual(len((self.out / "release.json.sig").read_bytes()), 64)

    def test_signature_is_over_context_and_manifest(self):
        self.assertEqual(self.release()[0], 0)
        body = (self.out / "release.json").read_bytes()
        rs = (self.out / "release.json.sig").read_bytes()
        public = sign_ota.header_public_raw()
        self.assertTrue(sign_ota.signature_valid(public, sign_ota.RELEASE_CONTEXT + body, rs))
        self.assertFalse(sign_ota.signature_valid(public, body, rs))
        self.assertFalse(sign_ota.signature_valid(public, sign_ota.RELEASE_CONTEXT + body + b" ", rs))

    def test_verify_release_accepts_then_refuses_changes(self):
        self.assertEqual(self.release()[0], 0)
        for f in (self.apk, self.zip):
            (self.out / f.name).write_bytes(f.read_bytes())
        rc, text = self.run_cli("verify-release", str(self.out))
        self.assertEqual(rc, 0, text)
        (self.out / self.apk.name).write_bytes(b"apk bytez")
        rc, text = self.run_cli("verify-release", str(self.out))
        self.assertEqual(rc, 1)
        self.assertIn("MISMATCH", text)

    def test_verify_release_refuses_tampered_manifest(self):
        self.assertEqual(self.release()[0], 0)
        path = self.out / "release.json"
        path.write_text(path.read_text().replace("9.9.9", "9.9.8"))
        rc, text = self.run_cli("verify-release", str(self.out))
        self.assertEqual(rc, 1)
        self.assertIn("BAD SIGNATURE", text)

    def test_refuses_key_that_is_not_in_the_header(self):
        other = make_key(self.dir, "other.pem")
        rc, text = self.run_cli(
            "release", "--key", str(other), "--version", "9.9.9", "--build", "3",
            "--out", str(self.out), str(self.apk),
        )
        self.assertEqual(rc, 1)
        self.assertIn("does not match", text)
        self.assertFalse((self.out / "release.json").exists())

    def test_refuses_bad_version_and_names(self):
        rc, _ = self.run_cli(
            "release", "--key", str(self.key), "--version", "9.9", "--build", "3",
            "--out", str(self.out), str(self.apk),
        )
        self.assertEqual(rc, 1)
        bad = self.dir / "bad name.apk"
        bad.write_bytes(b"x")
        rc, _ = self.run_cli(
            "release", "--key", str(self.key), "--version", "9.9.9", "--build", "3",
            "--out", str(self.out), str(bad),
        )
        self.assertEqual(rc, 1)
        rc, _ = self.run_cli(
            "release", "--key", str(self.key), "--version", "9.9.9", "--build", "3",
            "--out", str(self.out), str(self.apk), str(self.apk),
        )
        self.assertEqual(rc, 1)

    def test_defaults_come_from_pubspec(self):
        version, build = sign_ota.pubspec_version()
        rc, text = self.run_cli("release", "--key", str(self.key), "--out", str(self.out), str(self.apk))
        self.assertEqual(rc, 0, text)
        manifest = json.loads((self.out / "release.json").read_text())
        self.assertEqual((manifest["version"], manifest["build"], manifest["tag"]), (version, build, f"v{version}"))


if __name__ == "__main__":
    unittest.main()
