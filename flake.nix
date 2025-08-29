# {
#   inputs = rec {
#     nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
#     flake-utils.url = "github:numtide/flake-utils";
#     zig.url = "github:mitchellh/zig-overlay";
#   };
#   outputs = inputs @ {
#     self,
#     nixpkgs,
#     flake-utils,
#     ...
#   }: let
#     overlays = [
#         (final: prev: rec {
#             zigpkgs = inputs.zig.packages.${prev.system};
#             zig = inputs.zig.packages.${prev.system}."0.14.1";
#         })
#     ];
#     systems = builtins.attrNames inputs.zig.packages;
#   in
#     flake-utils.lib.eachSystem systems (
#         system: let
#             pkgs = import nixpkgs {inherit overlays system;};
#         in rec {
#             devShells.default = pkgs.mkShell {
#                 nativeBuildInputs = with pkgs; [zig];
#             };
#             devShell = self.devShells.${system}.default;
#         }
#     );
# }
#
{
  inputs = rec {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls-overlay.url = "github:zigtools/zls";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = inputs.zig-overlay.packages.x86_64-linux.default;
    zls = inputs.zls-overlay.packages.x86_64-linux.zls.overrideAttrs (old: {
            nativeBuildInputs = [ zig ];
    });
  in
    {
        devShells.x86_64-linux.default = pkgs.mkShell {
            packages = with pkgs; [
                zls
                zig
            ];
        };
    };
}
