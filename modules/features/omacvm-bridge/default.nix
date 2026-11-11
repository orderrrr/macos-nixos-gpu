{ inputs, config, ... }:
let
  inherit (config.meta) username;
  bridgeModule = config.flake.modules.nixos.omacvm-bridge;
in
{
  # The Mac's side of the desktop through OmacVM Bridge, the Mac helper that ships in
  # OmacVM.app's Contents/Helpers: its Wi-Fi, sound, Bluetooth, display and media keys, its
  # time zone, and Noctalia's wallpaper sent to it. omacvm's guest client talks to it over
  # HTTP on 10.0.2.2:47831 (the Mac's 127.0.0.1); Noctalia shows it through the plugin in
  # ./plugin instead of Omarchy's widgets and OSD.
  #
  # The Bridge runs as a LaunchAgent, installed once on the Mac with omacvm's own script (it
  # makes its token on first start and asks for its permissions):
  #   bash <inputs.omacvm>/src/bridge/mac/install.sh \
  #     --prebuilt ~/.local/share/nixos-gpu-vm/OmacVM.app/Contents/Helpers/OmacVMBridge.app
  #
  # The token, which every request carries, is not in the store: it is copied once from the
  # Mac to ~/.config/omacvm-bridge/token, the path omacvm's clients read (Gestures' too), and
  # persisted:
  #   ssh nixos-gpu-vm 'umask 077 && mkdir -p ~/.config/omacvm-bridge && cat > ~/.config/omacvm-bridge/token' \
  #     < ~/Library/Application\ Support/omacvm-bridge/token
  flake.modules.nixos.omacvm-bridge =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      guest = "${inputs.omacvm}/src/bridge/guest";
      bridge =
        pkgs.runCommand "omacvm-bridge"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
          }
          ''
            install -Dm755 ${guest}/omacvm-bridge $out/bin/omacvm-bridge
            substituteInPlace $out/bin/omacvm-bridge --replace-fail '#!/bin/bash' '#!${pkgs.bash}/bin/bash'
            wrapProgram $out/bin/omacvm-bridge --prefix PATH : ${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.curl
                pkgs.gawk
                pkgs.gnused
                pkgs.iproute2
                pkgs.jq
                pkgs.python3 # checks the Bridge's proof, so the token never is on a command line
              ]
            }
          '';
      timezone = pkgs.runCommand "omacvm-timezone" { } ''
        install -Dm755 ${guest}/omacvm-timezone $out/bin/omacvm-timezone
        substituteInPlace $out/bin/omacvm-timezone \
          --replace-fail '#!/usr/bin/python3' '#!${pkgs.python3}/bin/python3' \
          --replace-fail '"/usr/share/zoneinfo"' '"/etc/zoneinfo"'
      '';
      # Run by Noctalia's hooks (noctalia.toml): its wallpaper becomes the Mac's on every
      # display and Space, and so behind macOS's lock screen too.
      wallpaper = pkgs.writeShellApplication {
        name = "omacvm-wallpaper";
        runtimeInputs = [
          bridge
          config.programs.noctalia.package
          pkgs.coreutils
          pkgs.file
          pkgs.imagemagick
        ];
        text = ''
          # The changed one's path, or at Noctalia's start the one it shows.
          path=''${NOCTALIA_WALLPAPER_PATH:-$(noctalia msg wallpaper-get)}
          [ -f "$path" ] || exit 0
          # Each picture once: the Bridge rewrites every Space's wallpaper and macOS redraws.
          key="$path $(stat -c %Y "$path")"
          sent=''${XDG_STATE_HOME:-$HOME/.local/state}/omacvm-bridge/wallpaper-sent
          [ "$(cat "$sent" 2>/dev/null)" != "$key" ] || exit 0
          picture=$path
          # The Bridge takes PNG and JPEG only; Noctalia shows WebP and the rest too.
          case $(file -b --mime-type "$path") in
            image/png | image/jpeg) ;;
            *)
              picture=$(mktemp --suffix .png)
              trap 'rm -f "$picture"' EXIT
              magick "''${path}[0]" -strip "$picture" # the first frame of an animation
              ;;
          esac
          omacvm-bridge wallpaper "$picture" > /dev/null
          mkdir -p "''${sent%/*}"
          printf '%s' "$key" > "$sent"
        '';
      };
      # The client's path is put in, as Noctalia's service doesn't get the system's PATH.
      plugin = pkgs.runCommand "noctalia-plugin-mac" { } ''
        cp -r ${./plugin} $out
        chmod -R u+w $out
        substituteInPlace $out/events.luau $out/launcher.luau --replace-fail @bridge@ ${bridge}/bin/omacvm-bridge
      '';
      # Noctalia reads every *.toml in its config directory. The widget goes on a bar as "mac".
      noctaliaConfig = pkgs.writeText "omacvm-bridge.toml" ''
        [plugins]
        enabled = ["nixos-gpu-vm/mac"]

        [widget.mac]
        type = "nixos-gpu-vm/mac:status"

        [hooks]
        started = "${lib.getExe wallpaper}"
        wallpaper_changed = "${lib.getExe wallpaper}"
      '';
    in
    {
      environment.systemPackages = [ bridge ];

      # As omacvm's unit: root sets the zone with timedatectl, from the Bridge's "timezone"
      # events (at every start and when the Mac's zone changes), read with the user's token.
      # A zone set by hand in the VM is kept until it is the Mac's again.
      systemd.services.omacvm-timezone = {
        description = "OmacVM: the VM's time zone follows the Mac's";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.systemd ]; # timedatectl
        environment.OMACVM_TZ_CLIENT = "${bridge}/bin/omacvm-bridge";
        # It retries by itself while the Mac's side is away (asleep, Bridge restarting).
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          ExecStart = "${timezone}/bin/omacvm-timezone";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
      # timedated refuses a zone that NixOS sets. Without one the VM is on UTC from boot
      # until the Bridge answers (/etc is on the tmpfs).
      time.timeZone = lib.mkForce null;

      systemd.user.tmpfiles.rules = [
        "d %h/.local/share/noctalia/plugins"
        "L+ %h/.local/share/noctalia/plugins/mac - - - - ${plugin}"
        "L+ %h/.config/noctalia/omacvm-bridge.toml - - - - ${noctaliaConfig}"
      ];
      environment.persistence."/persist".users.${username}.directories = [
        ".local/state/omacvm-bridge" # the wallpaper the Mac has
      ];
    };

  # sudo and polkit ask the Mac's Touch ID first (omacvm's ADR 0041), through OmacVM.app's
  # virtio port org.omacvm.auth; the app relays to the Bridge, which shows Touch ID only for
  # the person at the VM's screen while its window is in front. Any other answer (no Mac, no
  # key, cancelled) is the password prompt as before.
  #
  # The request is signed with this VM's Touch ID key, which the Mac holds as
  # vm-keys/<first 32 hex of sha256("app/nixos-gpu-vm")>.touchid. One-time step, on the Mac:
  #   d=~/Library/Application\ Support/omacvm/vm-keys; mkdir -p "$d"; chmod 700 "$d"
  #   k="$d/$(printf app/nixos-gpu-vm | shasum -a 256 | cut -c1-32).touchid"
  #   [ -s "$k" ] || (umask 077; openssl rand -hex 32 > "$k")
  #   ssh nixos-gpu-vm 'sudo install -m600 /dev/stdin /var/lib/omacvm/touchid-key' < "$k"
  flake.modules.nixos.omacvm-touchid =
    { config, pkgs, ... }:
    let
      guest = "${inputs.omacvm}/src/bridge/guest";
      touchid = pkgs.runCommand "omacvm-touchid" { } ''
        install -Dm755 ${guest}/omacvm-touchid $out/bin/omacvm-touchid
        # The key lives in persisted /var/lib/omacvm, as /etc is on the tmpfs; the client
        # takes only a regular file of root's alone, so it can't be an impermanence symlink.
        substituteInPlace $out/bin/omacvm-touchid \
          --replace-fail '#!/usr/bin/python3 -I' '#!${pkgs.python3}/bin/python3 -I' \
          --replace-fail '"/usr/bin/loginctl"' '"${pkgs.systemd}/bin/loginctl"' \
          --replace-fail '"/usr/share/polkit-1/actions"' '"/run/current-system/sw/share/polkit-1/actions"' \
          --replace-fail 'pwd.getpwnam("polkitd")' 'pwd.getpwnam("polkituser")' \
          --replace-fail 'p = f"{ETC}/{name}"' 'p = f"/var/lib/omacvm/{name}"'
        install -Dm755 ${guest}/omacvm-touchid-note $out/bin/omacvm-touchid-note
        substituteInPlace $out/bin/omacvm-touchid-note --replace-fail 'PATH=/usr/bin:/bin' 'PATH=${pkgs.coreutils}/bin'
      '';
      # Before polkit's own rules (00-), so every check is noted: polkit's Touch ID is asked
      # only right after a check of the person at the screen.
      rule = pkgs.runCommand "00-omacvm-touchid.rules" { } ''
        substitute ${guest}/00-omacvm-touchid.rules $out \
          --replace-fail /usr/lib/omacvm/omacvm-touchid-note ${touchid}/bin/omacvm-touchid-note
      '';
      firstAuth = service: {
        rules.auth.omacvm-touchid = {
          order = config.security.pam.services.${service}.rules.auth.unix.order - 10;
          control = "sufficient";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "seteuid"
            "stdout"
            "${touchid}/bin/omacvm-touchid"
          ];
        };
      };
    in
    {
      imports = [ bridgeModule ]; # /etc/omacvm/env says this VM asks through the app's port
      security.pam.services.sudo = firstAuth "sudo";
      security.pam.services.polkit-1 = firstAuth "polkit-1";
      # pkexec asks polkit, so Touch ID too; nixpkgs leaves its setuid wrapper out by default.
      security.polkit.enablePkexecWrapper = true;

      # The port is root's alone, so no user program can open it or hold it open.
      services.udev.extraRules = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="org.omacvm.auth", OWNER="root", GROUP="root", MODE="0600"
      '';
      environment.etc."polkit-1/rules.d/00-omacvm-touchid.rules".source = rule;
      # The rule's notes, which polkitd writes from its read-only sandbox.
      systemd.tmpfiles.rules = [ "d /run/omacvm-touchid 0700 polkituser polkituser -" ];
      systemd.services.polkit.serviceConfig.ReadWritePaths = [ "-/run/omacvm-touchid" ];
      # polkit's PAM runs in a helper without devices; it may open the port, nothing else.
      systemd.services."polkit-agent-helper@".serviceConfig = {
        BindPaths = [ "-/dev/virtio-ports/org.omacvm.auth" ];
        DeviceAllow = [ "char-virtio-portsdev rw" ];
      };
    };
}
