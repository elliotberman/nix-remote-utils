finalPkgs: prevPkgs:
prevPkgs.lib.packagesFromDirectoryRecursive {
  inherit (prevPkgs) callPackage;
  directory = ./pkgs;
}
