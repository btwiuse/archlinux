#!/usr/bin/env bash
set -euo pipefail

: "${ARCH:?ARCH required}"
: "${IMAGE:?IMAGE required}"

docker push "${IMAGE}:bootstrap-${ARCH}"
docker push "${IMAGE}:base-${ARCH}"