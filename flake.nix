{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      unstable = import nixpkgs {
        config = {
          allowUnfree = true;
          cudaSupport = true;
          cudaCapabilities = [ "7.5" "8.0" "8.6" "8.9" "9.0" ];
        };
      };
    in
    {
      packages = forAllSystems (system: unstable.callPackage ./default.nix {});

      devShells = forAllSystems (system: {
        default = unstable.mkShellNoCC {
          packages = with unstable; [
            (callPackage ./default.nix {})
          ];
        };
      });
    };
}