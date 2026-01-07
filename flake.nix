{
  description = "Always up-to-date Nix package for taws (Terminal UI for AWS) with automated updates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        taws = pkgs.callPackage ./package.nix { };
      in
      {
        packages = {
          default = taws;
          taws = taws;
        };

        apps = {
          default = {
            type = "app";
            program = "${taws}/bin/taws";
          };
          taws = {
            type = "app";
            program = "${taws}/bin/taws";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustc
            cargo
            pkg-config
            openssl
            nix-prefetch-github
            jq
            curl
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            libiconv
          ];
        };
      }
    ) // {
      # Overlay for use with nixpkgs
      overlays.default = final: prev: {
        taws = final.callPackage ./package.nix { };
      };

      # Home Manager module
      homeManagerModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.programs.taws;
        in
        {
          options.programs.taws = {
            enable = mkEnableOption "taws - Terminal UI for AWS";
            package = mkOption {
              type = types.package;
              default = pkgs.callPackage ./package.nix { };
              description = "The taws package to use";
            };
          };

          config = mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };
    };
}
