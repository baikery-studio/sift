#!/usr/bin/env bash
# kernel/packet.sh — packet frontmatter access.
_PKTSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_PKTSH_DIR/config.sh"
SIFT_PACKETS="${SIFT_PACKETS:-$(config_path packets)}"

# packet_field PACKET_ID FIELD
packet_field() {
  python3 "$_PKTSH_DIR/_packet.py" "$SIFT_PACKETS/$1.md" "$2"
}
