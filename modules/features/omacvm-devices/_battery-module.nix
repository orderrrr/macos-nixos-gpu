# omacvm's battery kernel module (BAT0, ADP0) for this VM's kernel, where omacvm builds it with
# DKMS. Built as nixpkgs builds v4l2loopback.
{
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  src,
}:

let
  kernelBuild = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
in
stdenv.mkDerivation {
  pname = "omacvm-battery";
  version = "1.1.0"; # module/dkms.conf; the agent sends current_now and power_now from 1.1.0
  inherit src;
  __structuredAttrs = true;
  strictDeps = true;
  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags = kernelModuleMakeFlags ++ [ "KERNELRELEASE=${kernel.modDirVersion}" ];

  # Kbuild directly, as omacvm's dkms.conf does; the Makefile has no install target.
  buildPhase = ''
    runHook preBuild
    make -C ${kernelBuild} M=$(pwd) "''${makeFlags[@]}" modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make -C ${kernelBuild} M=$(pwd) "''${makeFlags[@]}" DEPMOD=true INSTALL_MOD_PATH=$out modules_install
    runHook postInstall
  '';
}
