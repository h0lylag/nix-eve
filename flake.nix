{
  description = "EVE Online launcher using UMU and Proton GE";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          eve-online = pkgs.callPackage ./pkgs/eve-online/package.nix { };
        in
        {
          inherit eve-online;
          default = eve-online;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      overlays.default = final: _prev: {
        eve-online = final.callPackage ./pkgs/eve-online/package.nix { };
      };
    };
}
