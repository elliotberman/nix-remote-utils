{
  lib,
  stdenv,
  jq,
  nix-copy-as,
  nix-output-monitor,
  complgen,
  installShellFiles,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "nor";
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
    cp nor.bash $out/bin/nor
    chmod +x $out/bin/nor

    wrapProgram $out/bin/nor \
      --prefix PATH : ${lib.makeBinPath [
        jq
        nix-copy-as
        nix-output-monitor
      ]}

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    complgen --bash nor.bash nor.usage
    complgen --fish nor.fish nor.usage
    complgen --zsh _nor nor.usage

    installShellCompletion --cmd nor \
      --bash nor.bash \
      --fish nor.fish \
      --zsh _nor
  '';

  meta = {
    description = "A wrapper around nom build that also runs the resulting output";
    license = lib.licenses.mit;
    mainProgram = "nor";
  };
}
