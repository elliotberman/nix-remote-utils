{
  lib,
  nix,
  nix-output-monitor,
  writeShellApplication,
}:
writeShellApplication {
  name = "nor";
  runtimeInputs = [
    nix
    nix-output-monitor
  ];
  text = lib.fileContents ./nbr.bash;
}
