#!/bin/sh
# Boot the VM (after ./build.sh), with this checkout shared into the guest as /etc/nixos.
# Extra arguments go to steamac's launcher, e.g. ./run.sh --cpus 8 --mem 16384
here=$(cd "$(dirname "$0")" && pwd)
NIXOS_GPU_VM=$here exec nix run "$here" -- "$@"
