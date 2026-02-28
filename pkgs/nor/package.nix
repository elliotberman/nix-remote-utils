{
  lib,
  jq,
  nix-copy-as,
  nix-output-monitor,
  writeShellApplication,
}:
writeShellApplication {
  name = "nor";
  runtimeInputs = [
    jq
    nix-copy-as
    nix-output-monitor
  ];
  text = lib.fileContents ./nor.bash;
}
