show_help() {
  SOURCE_DATE_EPOCH=1 man @mandir@/nbr.1*
}

usage() {
  echo "Usage: nbr -b HOST [OPTIONS] INSTALLABLE..."
  echo "Try 'nbr --help' for more information."
}

# Parse flags
no_check_sigs=""
keep_going=""
remote=""
positional_args=()

# Check if nom is available, fallback to nix
nix="nom"
if ! command -v "$nix" &>/dev/null; then
  nix="nix"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
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
        usage >&2
        exit 1
      fi
      remote="$2"
      shift 2
      ;;
    -*)
      echo "Error: unknown option $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

errors=()
if [[ -z "$remote" ]]; then
  errors+=("--builder is required")
fi

if (( ${#positional_args[@]} < 1 )); then
  errors+=("At least one installable is required")
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  for error in "${errors[@]}"; do
    echo "Error: $error" >&2
  done
  usage >&2
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
mapfile -t paths < <("$nix" build "${build_args[@]}" --store "ssh-ng://$remote" --builders "ssh-ng://$remote" --no-link --print-out-paths $keep_going)

# Copy built outputs back to local machine
echo "Copying build outputs from $remote..."
nix copy --from "ssh-ng://$remote" $no_check_sigs "${paths[@]}"
for path in "${paths[@]}" ; do
  echo "  $path"
done
