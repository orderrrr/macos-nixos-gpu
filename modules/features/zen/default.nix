{ inputs, config, ... }:
{
  # Not in nixpkgs; the flake repackages Zen's release builds.
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.nixos.zen =
    { pkgs, ... }:
    let
      # Read before autoconfig (mozilla.cfg), which comes too late for these: Firefox reads them
      # once at startup. WebGPU on Venus; allow-in-parent because Zen on Linux runs it without a
      # GPU process.
      userJs = pkgs.writeText "user.js" ''
        user_pref("dom.webgpu.enabled", true);
        user_pref("dom.webgpu.allow-in-parent", true);
      '';
    in
    {
      # In every profile (their folders are named at random when Zen makes them).
      systemd.user.services.zen-user-js = {
        description = "Zen's user.js in each profile";
        wantedBy = [ "default.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          for profile in "$HOME"/.config/zen/*.*/; do
            [ -d "$profile" ] && ln -sf ${userJs} "$profile/user.js"
          done
        '';
      };
      environment.persistence."/persist".users.${config.meta.username}.directories = [ ".config/zen" ]; # the profile
      environment.systemPackages = [
        # No "make Zen your default browser" prompt at every start. Set as an autoconfig pref: the
        # flake drops extraPolicies before wrapFirefox, which then writes an empty policies.json.
        (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
          extraPrefs = ''pref("browser.shell.checkDefaultBrowser", false);'';
        })
      ];
    };
}
