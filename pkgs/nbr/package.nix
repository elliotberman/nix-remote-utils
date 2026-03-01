{
  lib,
  stdenv,
  nix,
  nix-output-monitor,
  complgen,
  installShellFiles,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "nbr";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
    complgen
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp nbr.bash $out/bin/nbr
    chmod +x $out/bin/nbr

    wrapProgram $out/bin/nbr \
      --prefix PATH : ${lib.makeBinPath [
        nix
        nix-output-monitor
      ]}

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    complgen --bash nbr.bash nbr.usage
    complgen --fish nbr.fish nbr.usage
    complgen --zsh _nbr nbr.usage

    installShellCompletion --cmd nbr \
      --bash nbr.bash \
      --fish nbr.fish \
      --zsh _nbr
  '';

  meta = {
    description = "Build on remote machines via SSH";
    license = lib.licenses.mit;
    mainProgram = "nbr";
  };
}
