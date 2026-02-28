{
  lib,
  lsof,
  nix,
  nix-output-monitor,
  nix-serve-ng,
  openssh,
  writeShellApplication,
}:
writeShellApplication {
  name = "nix-copy-as";
  runtimeInputs = [
    lsof
    nix
    nix-output-monitor
    nix-serve-ng
    openssh
  ];
  text = lib.fileContents ./nix-copy-as.bash;
}
