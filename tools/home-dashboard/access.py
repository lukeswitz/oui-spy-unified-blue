# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""Who may talk to the dashboard.

The dashboard binds 127.0.0.1 and trusts only this computer. Letting other devices in is an explicit
choice (--lan), and from then on every device that is not this computer needs the access token.
Only a SHA-256 of the token is kept on disk (0600, outside the repo); the token itself is shown
once, when it is made.
"""
import hashlib
import hmac
import os
import secrets
from urllib.parse import urlsplit

LOOPBACK = ("127.0.0.1", "::1", "::ffff:127.0.0.1")
TOKEN_HASH_FILE = os.path.expanduser("~/.config/ouispy/dashboard_token.sha256")
SAFE_METHODS = ("GET", "HEAD", "OPTIONS")


def hash_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class TokenStore:
    def __init__(self, path=TOKEN_HASH_FILE):
        self.path = path

    def _read(self):
        try:
            with open(self.path) as f:
                return f.read().strip() or None
        except OSError:
            return None

    def exists(self):
        return self._read() is not None

    def create(self):
        """Make a new token, keep only its hash, return the token (shown once, never again)."""
        token = secrets.token_urlsafe(24)
        os.makedirs(os.path.dirname(self.path), mode=0o700, exist_ok=True)
        tmp = self.path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(hash_token(token) + "\n")
        os.replace(tmp, self.path)
        return token

    def verify(self, token):
        want = self._read()
        return bool(want and token) and hmac.compare_digest(hash_token(token), want)


def is_local(peer, forwarded_for=""):
    """This computer only: a loopback peer that is not relaying someone else (a proxy sets X-Forwarded-For)."""
    return peer in LOOPBACK and not forwarded_for


def host_allowed(host_header, port, lan):
    """DNS-rebinding guard: when bound to loopback only the loopback names are accepted as Host."""
    if lan:
        return True
    host = (host_header or "").lower()
    return host in (f"127.0.0.1:{port}", f"localhost:{port}", f"[::1]:{port}", "127.0.0.1", "localhost", "[::1]")


def origin_allowed(method, origin, host_header):
    """A page on another site must not be able to make this browser change anything."""
    if method in SAFE_METHODS or not origin:
        return True
    try:
        return urlsplit(origin).netloc.lower() == (host_header or "").lower()
    except ValueError:
        return False


def authorized(peer, forwarded_for, token_given, tokens):
    if is_local(peer, forwarded_for):
        return True
    return tokens.verify(token_given or "")
