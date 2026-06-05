#!/usr/bin/env bash
# Software profile W4 — structural wiring witness (delegates to _w4.py).
# Contract: witness_w4 <packet_path> <packet_id> -> { ok, reason }
set -euo pipefail
W4_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
witness_w4() { python3 "$W4_HERE/_w4.py" "$1" "$2"; }
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then witness_w4 "$@"; fi
