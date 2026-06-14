#!/usr/bin/env python3
"""Canonical JSON for the hash chain — the SINGLE source of truth (stdlib only).

The event_hash is computed in _log.py (append) and re-derived in _state.py (verify). The
canonicalization MUST be byte-identical between them or every chain silently breaks. This was
duplicated in both files with a comment begging they stay identical; it now lives here and is
imported by both.

NFC-normalize so equal-looking unicode (NFD vs NFC) hashes identically; sort_keys +
separators + ensure_ascii=False fix the byte form.
"""
import json
import unicodedata


def canon(obj):
    return unicodedata.normalize(
        "NFC", json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    )
