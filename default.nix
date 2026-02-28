{ pkgs }:
import ./nix/nix-remote-utils.nix { inherit (pkgs) lib callPackage; }
