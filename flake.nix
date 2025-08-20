{
  inputs = rec {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    overlays = [
        (final: prev: rec {
            zigpkgs = inputs.zig.packages.${prev.system};
            zig = inputs.zig.packages.${prev.system}."0.14.1";
        })
    ];
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
        system: let
            pkgs = import nixpkgs {inherit overlays system;};
        in rec {
            devShells.default = pkgs.mkShell {
                nativeBuildInputs = with pkgs; [zig];
            };
            devShell = self.devShells.${system}.default;
        }
    );
}
