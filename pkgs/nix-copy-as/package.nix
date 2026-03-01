{
  lib,
  stdenv,
  lsof,
  nix,
  nix-output-monitor,
  nix-serve-ng,
  openssh,
  complgen,
  installShellFiles,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "nix-copy-as";
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
    cp nix-copy-as.bash $out/bin/nix-copy-as
    chmod +x $out/bin/nix-copy-as

    wrapProgram $out/bin/nix-copy-as \
      --prefix PATH : ${lib.makeBinPath [
        lsof
        nix
        nix-output-monitor
        nix-serve-ng
        openssh
      ]}

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    complgen --bash nix-copy-as.bash nix-copy-as.usage
    complgen --fish nix-copy-as.fish nix-copy-as.usage
    complgen --zsh _nix-copy-as nix-copy-as.usage

    installShellCompletion --cmd nix-copy-as \
      --bash nix-copy-as.bash \
      --fish nix-copy-as.fish \
      --zsh _nix-copy-as
  '';

  meta = {
    description = "Copy Nix closures to remote machines as a trusted user";
    license = lib.licenses.mit;
    mainProgram = "nix-copy-as";
  };
}
