#!/usr/bin/env bash
# Copyright (c) 2026 Luke Switzer
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
if [ -n "${DRONEID_REPO:-}" ]; then python3 -I test/host/gen_vectors.py "$DRONEID_REPO"; fi
clang -c -Itest/host/stub -Isrc -o "$out/odid.o" src/opendroneid.c
clang -c -Itest/host/stub -Isrc -o "$out/wifi.o" src/wifi.c
clang++ -std=c++17 -Isrc -Itest/host/stub -o "$out/odidtest" test/host/skyspy_odid_test.cpp "$out/odid.o" "$out/wifi.o"
"$out/odidtest"
clang++ -std=c++17 -Wall -Wextra -Isrc -o "$out/zb154test" test/host/ieee802154_test.cpp
"$out/zb154test"
