# nix-remote-utils

A collection of utilities I find useful for building and copying Nix packages to/from remote machines.

## Packages

- **nbr** - build on any remote machine which is ssh-able
- **nor** - A wrapper around "nom build" that also runs the resulting output, possibly on a remote machine
- **nix-copy-as** - Copy Nix store paths to a remote host via a trusted user, possibly with sudo

## Quick Start

```bash
# Try without installing
nix run github:elliotberman/nix-remote-utils#nbr -- --help
nix run github:elliotberman/nix-remote-utils#nor -- --help
nix run github:elliotberman/nix-remote-utils#nix-copy-as -- --help
```

## Installation

### Using nix profile

```bash
# Install individual tools
nix profile install github:elliotberman/nix-remote-utils#nbr
nix profile install github:elliotberman/nix-remote-utils#nor
nix profile install github:elliotberman/nix-remote-utils#nix-copy-as
```

### Using Nix Flakes

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-remote-utils.url = "github:elliotberman/nix-remote-utils";
  };

  outputs = { self, nixpkgs, nix-remote-utils, ... }: {
    # NixOS configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = [ nix-remote-utils.overlays.default ];
          environment.systemPackages = with pkgs; [
            nbr
            nor
            nix-copy-as
          ];
        }
      ];
    };
  };
}
```

### Using Home Manager

With Home Manager, add to your configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-remote-utils.url = "github:elliotberman/nix-remote-utils";
  };

  outputs = { self, nixpkgs, home-manager, nix-remote-utils, ... }: {
    homeConfigurations."username" = home-manager.lib.homeManagerConfiguration {
      modules = [
        {
          nixpkgs.overlays = [ nix-remote-utils.overlays.default ];
          home.packages = with pkgs; [
            nbr
            nor
            nix-copy-as
          ];
        }
      ];
    };
  };
}
```

