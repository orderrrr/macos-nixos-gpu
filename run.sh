#!/bin/sh
# Boot the VM (after ./build.sh), with this checkout shared into the guest as /etc/nixos.
# Defaults to 10 vCPUs (this Mac's performance cores) and 8 GB; extra arguments go to steamac's
# launcher and override them (it takes the last value given), e.g. ./run.sh --mem 16384
here=$(cd "$(dirname "$0")" && pwd)
NIXOS_GPU_VM=$here exec nix run "$here" -- --cpus 10 --mem 8192 "$@"
