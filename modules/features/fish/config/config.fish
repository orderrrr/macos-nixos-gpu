status is-interactive; or return

# ============================================================================
# Environment Variables & Settings
# ============================================================================
set NVIM_MODE dev

# Common paths (both OS)
set -l common_paths \
    ~/.cargo/bin \
    ~/.local/bin \
    ~/.local/share/cargo/bin \
    ~/.bin/nvim/bin/ \
    ~/.bin \
    ~/.bin/slang/bin \
    /run/current-system/sw/bin \
    /etc/profiles/per-user/$USER/bin
    # /usr/local/bin

for p in $common_paths
    fish_add_path --append --path $p
end

# Ensure system binaries take priority over nix (fixes Steam/Proton)
fish_add_path --prepend /usr/bin

# Load OS-specific config
source ~/.config/fish/os.fish

# Fish settings
set -g fish_greeting ""
set -g fish_key_bindings fish_vi_key_bindings

set -g OPENCODE_ENABLE_EXA 1

# Core environment
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx PAGER less
set -gx LESS -RFX
set -gx GPG_TTY (tty)

set -gx TOKSCALE_API_URL http://sit-gravity.eus.v.co.zw/tokscale

# pi coding agent: use the nix-managed harness config dir
set -gx PI_CODING_AGENT_DIR ~/opt/pi-harness

# ============================================================================
# Shell Integrations
# ============================================================================
zoxide init fish | source
fzf_configure_bindings --directory=\ct --history=\cr --variables=\cv --git_status=\cg

# ============================================================================
# Aliases
# ============================================================================
alias e="$EDITOR"
alias ssh="TERM=xterm-256color command ssh"

bind \cl 'clear -x; commandline -f repaint'

# ============================================================================
# Functions
# ============================================================================

function __newline_before_prompt --on-event fish_prompt
    echo
end

function ls --description 'ls via lsd'
    lsd --group-directories-first --icon=auto $argv
end

function ll --description 'long ls via lsd'
    lsd -lAh --group-directories-first --icon=auto $argv
end

function lt --description 'tree via lsd'
    lsd --tree --icon=auto $argv
end

function pi --wraps pi --description 'run Pi without the global npm prefix'
    set -l pi_bin
    if set -q PI_NIX_LAUNCHER; and test -x "$PI_NIX_LAUNCHER"
        set pi_bin "$PI_NIX_LAUNCHER"
    else
        set pi_bin (type -P pi)
    end
    if test -z "$pi_bin"
        echo "pi: binary not found on PATH" >&2
        return 127
    end
    env -u NPM_CONFIG_PREFIX -u npm_config_prefix "$pi_bin" $argv
end


# /etc/fish/config.fish runs `brew shellenv` in interactive shells, which
# prepends /opt/homebrew/{bin,sbin} to PATH *after* devenv/nix activation,
# demoting nix-store entries. Move /nix/store/* paths back to the front.
if set -q DEVENV_PROFILE; or set -q IN_NIX_SHELL
    set -l _nix_paths
    set -l _other_paths
    for p in $PATH
        if string match -q '/nix/store/*' -- $p
            set -a _nix_paths $p
        else
            set -a _other_paths $p
        end
    end
    set -gx PATH $_nix_paths $_other_paths
end
