#!/usr/bin/env bash
set -euo pipefail
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$HOME/.platformio-c5}"
export PLATFORMIO_BUILD_DIR="${PLATFORMIO_BUILD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.pio/build-c5}"
PIO="${PIO:-$PLATFORMIO_CORE_DIR/penv/bin/pio}"
[ -x "$PIO" ] || PIO=pio
exec "$PIO" run -e "${OUISPY_C5_ENV:-v3_app_controlled_c5}" "$@"
