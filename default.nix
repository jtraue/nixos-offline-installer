{ niv ? import nix/sources.nix
, system ? builtins.currentSystem
, rootDevice
, nixosConfigDir ? ./.
, nixosConfigPath
, nixpkgs ? niv.nixpkgs
}:

with import nixpkgs { inherit system; };
with lib;

let

    # Cook the target os image
    installConfig = {
      installImage = {
        inherit nixosConfigDir rootDevice nixosConfigPath;
        nixpkgs.path = nixpkgs;
      };
    };

    installImage = (import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        installConfig
        ./modules/install-image.nix
      ];
    }).config.system.build.installImage;

    # Cook the shuttle to deliver target os image
    liveConfig = {
      targetImage = {
        tarball = installImage.tarball;
        config = installImage.config;
      };
    };

   liveImage = (import "${nixpkgs}/nixos/lib/eval-config.nix" {
    inherit system;
    modules = [
      "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      liveConfig
      ./modules/install-files.nix
      ./modules/live-image.nix
    ];
  }).config.system.build.isoImage;

in liveImage
