finalPkgs: prevPkgs:
import ./nix-remote-utils.nix { inherit (prevPkgs) lib callPackage; }
