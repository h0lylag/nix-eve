# nix-eve

Run EVE Online on NixOS with UMU and Proton GE. This flake provides an `eve-online` package.

## Installing

Add the overlay and package to your host flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-eve.url = "github:h0lylag/nix-eve";
    nix-eve.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-eve, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # ...
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ nix-eve.overlays.default ];

          environment.systemPackages = [ pkgs.eve-online ];
        })
      ];
    };
  };
}
```

If you haven’t already, enable unfree packages and 32-bit graphics as well.

``` nix
{
  nixpkgs.config.allowUnfree = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
```

## Running EVE

After rebuilding, run the installer to create the Wine prefix and install the
launcher:

```sh
eve-online --install
```

For subsequent launches, use the installed desktop entry or run:

```sh
eve-online
```

By default, the Wine prefix and game files are stored in `~/Games/eve-online`.

## Overrides

Package overrides set persistent defaults. Environment variables take precedence
at launch.

To change package defaults, use `.override` on `pkgs.eve-online`:

```nix
environment.systemPackages = [
  (pkgs.eve-online.override {
    extraEnvironment = {
      DXVK_HUD = "fps";
      PROTON_LOG = "1";
    };
    protonPackage = pkgs.proton-ge-bin;
    winePrefix = "/home/your-user/Games/eve-online";
  })
];
```

To apply the same settings to a single launch, set the corresponding environment
variables before the command:

```sh
DXVK_HUD=fps \
PROTON_LOG=1 \
EVE_WINEPREFIX="$HOME/Games/eve-online" \
PROTONPATH="/path/to/proton" \
eve-online
```

If automatic discovery does not find your launcher, you can also set
`EVE_LAUNCHER_EXE` to the absolute path of an existing launcher executable.
