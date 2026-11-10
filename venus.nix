# Venus-only Vulkan ICD (virtio), as steamac builds it (guest/mesa/container/common.sh).
# Mesa 26.2 lacks "venus: honor the virtio-gpu blob alignment" (MR !44783, first in 26.3), which
# the 16K-page macOS host needs, so this is steamac's pin: that MR's commit plus its patches.
{
  lib,
  stdenv,
  fetchFromGitLab,
  meson,
  ninja,
  pkg-config,
  python3,
  wayland-scanner,
  libdrm,
  wayland,
  wayland-protocols,
  libxcb,
  libx11,
  libxshmfence,
  libxrandr,
  zstd,
  zlib,
  expat,
}:

let
  venusProtocol = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "virgl";
    repo = "venus-protocol";
    rev = "ca19b6358d7cc491bc3e4de76f04c6700876a8fa"; # v1.1.3, the version Mesa's wrap names
    hash = "sha256-epSb26uLAbHYBDr+ju6rzFu4ozD/LUpRuou6hA/BFRM=";
  };
in
stdenv.mkDerivation {
  pname = "mesa-venus";
  version = "26.3.0-devel-4cf09890";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "mesa";
    repo = "mesa";
    rev = "4cf0989083d25b92d02c6fef2bed934ad77b4ecd";
    hash = "sha256-RQrv14zbOHjBct6nnaZnpThCiekA2ImhibWK1vi0Wr0=";
  };

  patches = [
    ./patches/mesa/0002-venus-avoid-null-ptr-dereference-for-zero-external-image-handleType.patch
    ./patches/mesa/0003-venus-query-KosmicKrisp-external-legacy-tiling.patch
  ];

  # The meson hook builds with wrap_mode=nodownload: the wrap's directory has to be there already.
  postUnpack = ''
    cp -r ${venusProtocol} $sourceRoot/subprojects/venus-protocol-1.1.3
    chmod -R u+w $sourceRoot/subprojects/venus-protocol-1.1.3
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    (python3.withPackages (p: [
      p.mako
      p.packaging
      p.pyyaml
    ]))
    wayland-scanner
  ];

  buildInputs = [
    libdrm
    wayland
    wayland-protocols
    libxcb
    libx11
    libxshmfence
    libxrandr
    zstd
    zlib
    expat
  ];

  mesonBuildType = "release";
  mesonAutoFeatures = "auto"; # as steamac's plain meson; the hook's "enabled" forces glvnd on

  mesonFlags = [
    "-Db_ndebug=true"
    "-Dvulkan-drivers=virtio"
    "-Dgallium-drivers="
    "-Dplatforms=x11,wayland"
    "-Dllvm=disabled"
    "-Dvideo-codecs="
    "-Dopengl=false"
    "-Dglx=disabled"
    "-Degl=disabled"
    "-Dgbm=disabled"
    "-Dgles1=disabled"
    "-Dgles2=disabled"
    "-Dvulkan-layers="
    "-Dtools="
    "-Dbuild-tests=false"
    "-Dvalgrind=disabled"
    "-Dlibunwind=disabled"
    "-Dlmsensors=disabled"
    "-Dxlib-lease=disabled"
    "-Dspirv-tools=disabled"
    "-Dzstd=enabled"
    "-Dzlib=enabled"
    "-Dexpat=enabled"
    "-Ddisplay-info=disabled"
    "-Dshader-cache=enabled"
  ];
}
