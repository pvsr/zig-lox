{
  description = "Zig implementation of Lox, from the book Crafting Interpreters";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems =
        mkOutputs:
        nixpkgs.lib.genAttrs [
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
          "x86_64-linux"
        ] (system: mkOutputs system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        _: pkgs: rec {
          lox = pkgs.stdenv.mkDerivation {
            pname = "lox";
            version = "0.0.1";
            src = ./.;
            nativeBuildInputs = [ pkgs.zig_0_15 ];
            meta.mainProgram = "lox";
            doCheck = true;
          };
          default = lox;
        }
      );

      checks = forAllSystems (
        system: pkgs: {
          default = pkgs.runCommand "zig-lox-test" { } ''
            echo 'print "hello" + " " + "world";' | ${
              self.packages.${system}.default
            }/bin/lox 2>&1| grep 'hello world'
            touch $out
          '';
        }
      );

      apps = forAllSystems (
        system: pkgs: {
          lox = {
            type = "app";
            program = pkgs.lib.getExe self.packages.${system}.lox;
          };
          default = self.apps.${system}.lox;
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.zig
              pkgs.zls
              pkgs.watchexec
            ];
          };
        }
      );
    };
}
