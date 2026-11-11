#!/bin/sh
# Set up a Mac to run the VM: fetch steamac at the commit this repo is tested with, build its
# macOS host stack (launcher, libkrun, virglrenderer, KosmicKrisp/MoltenVK), then the guest.
# Re-running is cheap: steamac's steps skip what is already built.
#
# Needs, once per Mac: Xcode (selected, with its Metal toolchain), Homebrew, rustup, and Nix
# with an aarch64-linux builder (nix-darwin's nix.linux-builder).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
steamac=${XDG_DATA_HOME:-$HOME/.local/share}/nixos-gpu-vm/steamac
rev=407fb58b7459c65f49a7c65ddb875718a093f43b

if ! xcrun -f metal > /dev/null 2>&1; then
	echo "Xcode's Metal compiler is missing. Run:" >&2
	echo "  sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -runFirstLaunch" >&2
	echo "  xcodebuild -downloadComponent MetalToolchain" >&2
	exit 1
fi
for tool in brew rustup nix; do
	command -v "$tool" > /dev/null || [ -x "/opt/homebrew/opt/$tool/bin/$tool" ] || {
		echo "$tool is missing" >&2
		exit 1
	}
done

[ -d "$steamac/.git" ] || git clone https://github.com/fxgl/steamac "$steamac"
git -C "$steamac" cat-file -e "$rev^{commit}" 2> /dev/null || git -C "$steamac" fetch origin
git -C "$steamac" checkout -q "$rev"
# Ours after steamac's: its libkrun and KosmicKrisp builds apply their patches/*.patch in order.
cp "$here"/modules/hosts/vm/libkrun/*.patch "$steamac/host/libkrun/patches/"
cp "$here"/modules/hosts/vm/kosmickrisp/*.patch "$steamac/host/kosmickrisp/patches/"
# Ours on steamac's launcher (Swift), in order: OmacVM's Mac side (battery, media, camera,
# Touch ID ports), full screen over the notch, quiet boot. Applied to a clean launcher tree, so
# re-running starts again from steamac's own sources.
git -C "$steamac" checkout -q "$rev" -- host/launcher
git -C "$steamac" clean -fq -- host/launcher/Sources/steamac-vm
git -C "$steamac" apply "$here"/modules/hosts/vm/launcher/*.patch

# steamac's patch merging expects plain two-sided conflict markers (a global zdiff3 breaks it);
# libkrun needs Homebrew's keg-only rustup and macOS's own mv ahead of GNU coreutils.
PATH=/opt/homebrew/opt/rustup/bin:/bin:$PATH \
	GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=merge.conflictStyle GIT_CONFIG_VALUE_0=merge \
	"$steamac/build.sh" host

nix build --no-link "$here#nixosConfigurations.vm.config.system.build.bundle"
