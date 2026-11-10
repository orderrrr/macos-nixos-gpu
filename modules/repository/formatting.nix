{ inputs, ... }:
{
  # `nix fmt` formats and lints the Nix files; `nix flake check` fails on anything it would change.
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt = {
    programs = {
      nixfmt.enable = true;
      statix.enable = true;
      deadnix.enable = true;
    };
    # Layout last, after the linters' rewrites, so one pass is final.
    settings.formatter.nixfmt.priority = 1;
  };
}
