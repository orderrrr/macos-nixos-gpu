#!/bin/sh
# Build the guest (on the nix-darwin linux-builder) and boot it in steamac's launcher.
# Extra arguments go to steamac-vm, e.g. ./run.sh --display 1920x1080 --cpus 8 --mem 16384
#
# disk.img is made once from the build's rootfs and holds the whole system, so it only boots
# the build it was made from. After a config change, delete disk.img to start over (this also
# wipes the guest's home).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
steamac=${STEAMAC:-$HOME/opt/testing/steamac}
disk=$here/disk.img

nix build "$here#bundle" -o "$here/result"
if [ ! -f "$disk" ]; then
	rootfs=$(nix build --no-link --print-out-paths "$here#rootfs")
	cp "$rootfs" "$disk"
	chmod u+w "$disk"
	truncate -s 64G "$disk" # sparse; the guest grows its filesystem on boot
	cp "$here/result/cmdline" "$disk.cmdline"
	nix store delete "$rootfs" # the copy is all we need; don't keep 6 GB in the store
fi
if ! cmp -s "$here/result/cmdline" "$disk.cmdline"; then
	echo "disk.img was made from a different build; delete disk.img (and with it the guest's home) to boot this one" >&2
	exit 1
fi

exec "$steamac/work/out/steamac-vm" \
	--kernel "$here/result/Image" \
	--initrd "$here/result/initrd" \
	--cmdline "$(cat "$here/result/cmdline")" \
	--disk "$disk" \
	--no-share \
	"$@"
