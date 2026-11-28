#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-camera.sh"
bash "$ROOT/scripts/build-location.sh"
