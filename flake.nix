{
  description = "Zig implementation of Lox, from the book Crafting Interpreters";

  inputs.nixpkgs.url = "github:ddogfoodd/nixpkgs/update-zig";

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
        system: pkgs:
        let
          zig = pkgs.zig_0_16;
        in
        {
          zlox = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "zlox";
            version = "0.0.1";
            src = nixpkgs.lib.cleanSource ./.;
            nativeBuildInputs = [ zig ];
            meta.mainProgram = "zlox";
            doCheck = true;
            zigDeps = zig.fetchDeps {
              inherit (finalAttrs) src pname version;
              hash = "sha256-cX1Ev7h7IpXN9q7/58Rqs2q4Mz8M2BtLYLSXjjpmcOc=";
            };
            postConfigure = ''
              ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
            '';
          });
          default = self.packages.${system}.zlox;
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
        _: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.zig_0_16
              pkgs.zls
            ];
          };
        }
      );
    };
}
