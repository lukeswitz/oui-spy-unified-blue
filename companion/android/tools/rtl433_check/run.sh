#!/usr/bin/env bash
# Copyright (c) 2026 Luke Switzer
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../../app/src/main/kotlin/com/rootdowndigital/ouispy/wifiadapter"
work="${RTL433_CHECK_DIR:-${TMPDIR:-/tmp}/rtl433_check}"
mkdir -p "$work"
if [ ! -d "$work/rtl_433_tests" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/merbanan/rtl_433_tests.git "$work/rtl_433_tests"
fi
dirs=("${@:-tests/acurite tests/ert tests/oregon_scientific}")
git -C "$work/rtl_433_tests" sparse-checkout set --no-cone $(for d in ${dirs[@]}; do printf "%s/* " "$d"; done)
kotlinc "$here/Rtl433Check.kt" "$src"/Rtl433*.kt -include-runtime -d "$work/rtl433_check.jar" 2>/dev/null
java -cp "$work/rtl433_check.jar" com.rootdowndigital.ouispy.wifiadapter.Rtl433CheckKt $(for d in ${dirs[@]}; do printf "%s " "$work/rtl_433_tests/$d"; done)
