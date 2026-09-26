# nix-eve

Run EVE Online on NixOS with UMU and Proton GE.

## Installing

Add nix-eve to your host flake:

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

If you haven't already, enable unfree packages and 32-bit graphics:

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

After rebuilding your system, run the installer to set up the Wine prefix and EVE launcher:

```sh
eve-online --install
```

After that, open EVE from your app menu or run:

```sh
eve-online
```

EVE keeps its Wine prefix and game files in `~/Games/eve-online` by default.

## Overrides

Package overrides set the defaults. Environment variables override those settings when you launch EVE.

Use `.override` on `pkgs.eve-online` to change the defaults:

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

For a single launch, you can set the same options with environment variables:

```sh
DXVK_HUD=fps \
PROTON_LOG=1 \
EVE_WINEPREFIX="$HOME/Games/eve-online" \
PROTONPATH="/path/to/proton" \
eve-online
```

If the launcher isn't found automatically, set `EVE_LAUNCHER_EXE` to the absolute path of its executable.

### EVE Preview Manager

If you cannot click [EVE Preview Manager](https://github.com/h0lylag/EVE-Preview-Manager) previews, disable Wine's pointer grabbing:

```nix
pkgs.eve-online.override { grabPointer = false; }
```

Or override it at launch:

```sh
EVE_GRAB_POINTER=N eve-online
```
