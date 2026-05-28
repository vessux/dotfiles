{ stdenvNoCC, lib }:

# Touch-ID-gated pinentry for rbw. Built with the host's /usr/bin/swiftc rather
# than nixpkgs' darwin Swift toolchain — the latter is fragile, particularly
# when linking Apple frameworks (LocalAuthentication, Security), and on a Mac
# the system swiftc is always present (Xcode CLT) and finds the SDK by itself.
# That makes the build mildly impure (depends on /usr/bin), but for a personal
# nix-darwin host that's a reasonable trade-off.

stdenvNoCC.mkDerivation {
  pname = "pinentry-rbw-touchid";
  version = "0.1.0";
  src = ./.;

  # nix's darwin stdenv strips PATH down so swiftc can't find its sibling tools
  # (xcrun, the real compiler under Xcode). We disable the chroot sandbox for
  # this build and put /usr/bin back on PATH so the host driver works.
  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # Scope the PATH override to swiftc: putting /usr/bin permanently on PATH
    # would shadow the nixpkgs coreutils/find that later phases (e.g. fixup)
    # depend on (BSD find vs GNU find -printf).
    #
    # nixpkgs' darwin stdenv otherwise pulls in an older (5.10-era) apple-sdk
    # via SDKROOT/NIX_* flags that the host swiftc (6.3.1) refuses, so we
    # pass -sdk explicitly. The swift driver needs xcrun on PATH to locate
    # sibling tools.
    HOST_SDK=$(env PATH=/usr/bin /usr/bin/xcrun --show-sdk-path)
    env PATH=/usr/bin:/bin /usr/bin/swiftc \
      -sdk "$HOST_SDK" -O -o pinentry-rbw-touchid main.swift \
      -framework LocalAuthentication -framework Security
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp pinentry-rbw-touchid $out/bin/pinentry-rbw-touchid
    chmod 755 $out/bin/pinentry-rbw-touchid
    runHook postInstall
  '';

  meta = {
    description = "Touch ID-gated pinentry for rbw (unofficial Bitwarden CLI)";
    platforms = [ "aarch64-darwin" "x86_64-darwin" ];
    mainProgram = "pinentry-rbw-touchid";
  };
}
