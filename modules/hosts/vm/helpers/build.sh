#!/usr/bin/env bash
# Build omacvm's two Mac helpers (OmacVM Bridge, OmacVM Gestures) with this directory's patches,
# so steamac's launcher window (steamac-vm) counts as a VM like OmacVM.app's.
#   build.sh            build into ~/.local/share/nixos-gpu-vm/omacvm-helpers/src/.../build
#   build.sh --install  build, then install both into ~/Applications with omacvm's install.sh
#                       (replaces the installed copies and their LaunchAgents)
# The clone (~/.local/share/nixos-gpu-vm/omacvm-src) is not touched: its committed src/ is
# exported into the work dir and patched there. The helpers come out ad-hoc signed (omacvm's
# lib/sign.sh, designated requirement = bundle id): macOS asks for Accessibility and Input
# Monitoring again once, after that rebuilds keep the permissions.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CLONE=${OMACVM_SRC:-$HOME/.local/share/nixos-gpu-vm/omacvm-src}
WORK=$HOME/.local/share/nixos-gpu-vm/omacvm-helpers

rm -rf "$WORK"; mkdir -p "$WORK"
git -C "$CLONE" archive HEAD src | tar -x -C "$WORK"
for p in "$HERE"/*.patch; do patch -d "$WORK" -p1 --forward --quiet < "$p"; done

"$WORK/src/gestures/mac/build.sh"
"$WORK/src/bridge/mac/build.sh"

if [[ ${1:-} == --install ]]; then
    "$WORK/src/gestures/mac/install.sh" --prebuilt "$WORK/src/gestures/mac/build/OmacVMGestures.app"
    "$WORK/src/bridge/mac/install.sh" --prebuilt "$WORK/src/bridge/mac/build/OmacVMBridge.app"
fi
