#!/usr/bin/env python3
import json
import sys

m = json.load(sys.stdin)
manifests = m.get("manifests", [])
print("manifests:", len(manifests))
for entry in manifests:
    plat = entry.get("platform", {})
    print("  {}/{}".format(plat.get("architecture", "?"), plat.get("os", "?")))
missing = []
for a in ["amd64", "386", "arm64", "riscv64"]:
    if not any(e.get("platform", {}).get("architecture") == a for e in manifests):
        missing.append(a)
if missing:
    print("::warning::multi-arch manifest :base is missing arches: " + ",".join(missing))
    sys.exit(0)
else:
    print("multi-arch manifest :base contains all 4 arches")