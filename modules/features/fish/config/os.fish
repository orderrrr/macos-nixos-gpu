# Linux-specific paths
set -l linux_paths \
    ~/.cargo/bin \
    ~/.local/bin \
    ~/.local/share/cargo/bin \
    ~/.bun/bin \
    /usr/local/bin

for p in $linux_paths
    test -d $p; and fish_add_path --move --path $p
end

# Vulkan
set -gx VULKAN_HOME /usr/share/vulkan
set -gx VULKAN_SDK /usr
# Clear macOS-specific Vulkan vars that may bleed in from a shared dotfiles environment
set -e VK_ICD_FILENAMES
set -e DYLD_FALLBACK_LIBRARY_PATH

# Browser
set -gx BROWSER xdg-open

# Linux aliases
# Installed home-manager, not `nix run github:...`, which fetches it from GitHub each run.
alias hms="home-manager switch --flake ~/opt/nix-config#order"

# Hyprland specific
if test -n "$HYPRLAND_INSTANCE_SIGNATURE"
    set -gx WAYLAND_DISPLAY wayland-1
end

# ROCm/HIP for AI/ML compute (gaming unaffected - uses separate Mesa path)
if test -d /opt/rocm
    set -gx ROCM_PATH /opt/rocm
    fish_add_path --move --path $ROCM_PATH/bin
    set -gx LD_LIBRARY_PATH $ROCM_PATH/lib $LD_LIBRARY_PATH
end
