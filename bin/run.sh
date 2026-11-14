#!/bin/sh
set -eu
PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script=$1
shift
export TCLLIBPATH="$PACKAGE_ROOT${TCLLIBPATH:+ $TCLLIBPATH}"
if [ -z "${TCLSH:-}" ]; then
    for interpreter in tclsh9.1 tclsh9.0 tclsh8.6 tclsh; do
        if command -v "$interpreter" >/dev/null 2>&1; then TCLSH=$interpreter; break; fi
    done
fi
exec "${TCLSH:-tclsh}" "$PACKAGE_ROOT/$script" "$@"
