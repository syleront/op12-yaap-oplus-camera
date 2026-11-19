#!/usr/bin/env bash
# Full build: native parts, our APKs, then the module zip (build/opcamera_yaap-<version>.zip).
# Needs payload/ first (tools/extract_payload.sh). See docs/BUILDING.md.
set -e
d=$(dirname "$0")
bash "$d/build_native.sh"
bash "$d/build_apps.sh"
bash "$d/build_module.sh"
