{
  lib,
  nix,
  nix-output-monitor,
  writeShellApplication,
}:
writeShellApplication {
  name = "nbr";
  runtimeInputs = [
    nix
    nix-output-monitor
  ];
  text = lib.fileContents ./nbr.bash;
}
