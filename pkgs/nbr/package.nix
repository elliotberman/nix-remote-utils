{
  lib,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "nor";
  runtimeInputs = [
    nix
  ];
  text = lib.fileContents ./nbr.bash;
}
