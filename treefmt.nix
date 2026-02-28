{
  lib,
  nixfmt,
  shfmt,
  treefmt,
  ...
}:
treefmt.withConfig {
  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "warn";

    formatter.nixfmt = {
      command = lib.getExe nixfmt;
      includes = [ "*.nix" ];
    };

    formatter.shfmt = {
      command = lib.getExe shfmt;
      options = [
        "-w"
        "-i"
        "2"
      ];
      includes = [
        "*.bash"
      ];
    };
  };
}
