#!/bin/sh
# Boot the VM (after ./build.sh), sharing ~/VM (with this checkout hidden in it as .nixos-gpu-vm).
# Defaults to 10 vCPUs (this Mac's performance cores) and 8 GB; extra arguments go to steamac's
# launcher and override them (it takes the last value given), e.g. ./run.sh --mem 16384
here=$(cd "$(dirname "$0")" && pwd)
exec nix run "$here" -- --cpus 10 --mem 8192 "$@"
