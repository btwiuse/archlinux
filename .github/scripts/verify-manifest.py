#!/usr/bin/env python3
"""Verify that a multi-arch manifest contains all four expected arches.

Reads a manifest list (v2) or OCI image index (v1) JSON document on stdin.
Reports per-tag completeness and exits with rc=0 on completeness, rc=1 on
a missing architecture. Missing arches are surfaced as ::warning lines so
the calling workflow's aggregate step stays green for partial successes.
"""
import json
import sys

EXPECTED = ["amd64", "386", "arm64", "riscv64"]
ARCH_LABEL = sys.argv[1] if len(sys.argv) > 1 else "the manifest"

m = json.load(sys.stdin)
manifests = m.get("manifests", [])
print("manifests:", len(manifests))
for entry in manifests:
    plat = entry.get("platform", {})
    print("  {}/{}".format(plat.get("architecture", "?"), plat.get("os", "?")))
missing = [
    a for a in EXPECTED
    if not any(e.get("platform", {}).get("architecture") == a for e in manifests)
]
if missing:
    print("::warning::" + ARCH_LABEL + " is missing arches: " + ",".join(missing))
    sys.exit(1)
print(ARCH_LABEL + " contains all 4 arches")
sys.exit(0)