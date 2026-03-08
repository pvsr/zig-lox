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
          zlox = pkgs.stdenv.mkDerivation {
            pname = "zlox";
            version = "0.0.1";
            src = ./.;
            nativeBuildInputs = [ pkgs.zig_0_15 ];
            meta.mainProgram = "zlox";
            doCheck = true;
          };
          default = zlox;
        }
      );

      checks = forAllSystems (
        system: pkgs: {
          default = pkgs.runCommand "zlox-test" { } ''
            echo 'print "hello" + " " + "world";' | ${
              self.packages.${system}.default
            }/bin/zlox 2>&1| grep 'hello world'
            touch $out
          '';
        }
      );

      apps = forAllSystems (
        system: pkgs: {
          zlox = {
            type = "app";
            program = pkgs.lib.getExe self.packages.${system}.zlox;
          };
          default = self.apps.${system}.zlox;
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
