usage() {
  cat <<EOF
nbr - build on any remote machine which is ssh-able

Usage: nbr [OPTIONS] --builder <remote> <installable>...

Arguments:
  <installable>...        One or more Nix installables to build (e.g., .#package or github:user/repo#package)

Options:
  -b, --builder <remote>  Remote SSH host to build on (required)
  --help                  Show this help message
  --no-check-sigs         Skip signature checking when copying derivations
  --keep-going            Continue building as many derivations as possible on failure

Description:
  Builds Nix derivations on remote machines by copying the derivations to
  the remote machine, so that your local machine doesn't need to copy
  intermediate artifacts. After building, the final build outputs are
  copied back to the local machine.

Examples:
  nbr --builder build-server .#mypackage
  nbr -b build-server .#mypackage .#anotherpackage
  nbr --no-check-sigs --builder build-server .#mypackage
  nbr --keep-going --no-check-sigs -b remote-host github:nixos/nixpkgs#hello .#local
EOF
}

# Parse flags
no_check_sigs=""
keep_going=""
remote=""
positional_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --no-check-sigs)
      no_check_sigs="--no-check-sigs"
      shift
      ;;
    --keep-going)
      keep_going="--keep-going"
      shift
      ;;
    -b|--builder)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: --builder requires a value" >&2
        echo >&2
        usage
        exit 1
      fi
      remote="$2"
      shift 2
      ;;
    -*)
      echo "Error: unknown option $1" >&2
      echo >&2
      usage
      exit 1
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$remote" ]]; then
  echo "Error: --builder is required" >&2
  echo >&2
  usage
  exit 1
fi

if (( ${#positional_args[@]} < 1 )); then
  echo "Error: expected at least one installable (got ${#positional_args[@]})" >&2
  echo >&2
  usage
  exit 1
fi

# Evaluate all installables and collect their drvPaths
drvPaths=()
echo "Evaluating installables..."
for installable in "${positional_args[@]}"; do
  echo "  Evaluating $installable..."
  drvPaths+=("$(nix eval --raw "$installable.drvPath")")
done

# Copy all drvPaths to remote in one step
echo "Copying ${#drvPaths[@]} derivation(s) to $remote..."
nix copy "${drvPaths[@]}" --to "ssh-ng://$remote" $no_check_sigs
echo "Copied derivations to $remote."

# Build all derivations on remote in one step
echo "Building ${#drvPaths[@]} derivation(s) on $remote..."
build_args=()
for drvPath in "${drvPaths[@]}"; do
  build_args+=("$drvPath^*")
done
mapfile -t paths < <(nom build "${build_args[@]}" --store "ssh-ng://$remote" --builders "ssh-ng://$remote" --no-link --print-out-paths $keep_going)

# Copy built outputs back to local machine
echo "Copying build outputs from $remote..."
nix copy --from "ssh-ng://$remote" $no_check_sigs "${paths[@]}"
for path in "${paths[@]}" ; do
  echo "  $path"
done
