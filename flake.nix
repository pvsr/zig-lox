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
        ] (system: mkOutputs nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        lox = pkgs.stdenv.mkDerivation {
          pname = "lox";
          version = "0.0.1";
          src = ./.;
          nativeBuildInputs = [ pkgs.zig_0_15 ];
          meta.mainProgram = "lox";
        };
        default = lox;
      });

      apps = forAllSystems (pkgs: {
        lox = {
          type = "app";
          program = pkgs.lib.getExe self.packages.${pkgs.system}.lox;
        };
        default = self.apps.${pkgs.system}.lox;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with self.packages.${pkgs.system}; [
            pkgs.zig
            pkgs.zls
            # lox
          ];
        };
      });
    };
}
