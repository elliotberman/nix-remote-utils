(($# != 2)) && {
  echo "expected two arguments (got $#): nbr <flakeURI> <remote>"
  return 1
}
flakeURI=$1
remote=$2
nix=nom

if command -v $nix >/dev/null 2>&1; then
  nix=nix
fi

echo "Evaluating $flakeURI..."
drvPath=$(nix eval --raw "$flakeURI.drvPath")
echo "Instantiated $drvPath."

echo "Copying $drvPath to $remote..."
nix copy "$drvPath" --to "ssh-ng://$remote"
echo "Copied $drvPath to $remote."

echo "Building $drvPath^* on $remote..."
$nix build "$drvPath^*" --store "ssh-ng://$remote" --builders "ssh-ng://$remote" --keep-going --print-out-paths
echo "Built $flakeURI on $remote."
