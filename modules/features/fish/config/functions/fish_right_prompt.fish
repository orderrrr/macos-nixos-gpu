function fish_right_prompt
    if set -q DEVENV_PROFILE
        set_color yellow
        echo -n "(devenv)"
        set_color normal
    else if set -q IN_NIX_SHELL
        set_color cyan
        echo -n "(nix:$IN_NIX_SHELL)"
        set_color normal
    end
end
