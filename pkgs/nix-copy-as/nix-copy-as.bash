set -euo pipefail

usage() {
  cat <<EOF
nix-copy-as - Copy Nix store paths to a remote host via nix-serve

This script emulates "nix copy --to" but works around signature checking by
using nix-serve as a temporary substituter.

Usage: nix-copy-as [OPTIONS] [INSTALLABLE...]

Required Arguments:
  --to [USERNAME@]HOST     SSH username and host to connect to

Optional Arguments:
  --user USERNAME        Username to run 'nix build' as on remote via sudo
                        (runs as SSH user if not specified)
  --no-check-sigs        Disable signature checking on the remote
  --verbose, -v          Enable verbose output (passed to nix build)
  --help                 Show this help message

Pass-through Arguments:
  All common evaluation options, flake-related options, and logging options
  are passed through to 'nix build'. See 'nix build --help' for details.

Installables:
  One or more Nix installables (e.g., nixpkgs#hello, .#package)

Example:
  nix-copy-as --to user@remote-host nixpkgs#hello
  nix-copy-as --to user@remote-host --no-check-sigs .#mypackage

How it works:
  1. Builds the installable(s) locally with nom
  2. Finds a free port (starting at 5001) and starts nix-serve
  3. SSH port-forwards the nix-serve to the remote
  4. Runs 'nix build' on remote using the forwarded substituter
EOF
  exit 1
}

# shellcheck disable=SC2329 # bad at figuring out trap
cleanup() {
  if [[ -n "${SERVE_PID:-}" ]] && kill -0 "$SERVE_PID" 2>/dev/null; then
    echo "Stopping nix-serve (PID: $SERVE_PID)..."
    kill "$SERVE_PID" 2>/dev/null || true
    wait "$SERVE_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

to_host=""
remote_user=""
no_check_sigs=""
installables=()
local_nix_args=()
logging_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --to)
    if [[ -z "${2:-}" ]]; then
      echo "Error: --to requires a value (username@host)"
      usage
    fi
    to_host="$2"
    shift 2
    ;;
  --user)
    if [[ -z "${2:-}" ]]; then
      echo "Error: --user requires a value"
      usage
    fi
    remote_user="$2"
    shift 2
    ;;
  --no-check-sigs)
    no_check_sigs="--no-check-sigs"
    shift
    ;;
  --help)
    usage
    ;;
  # Common evaluation options (local only, 2 args)
  --arg | --arg-from-file | --argstr | --override-flake)
    local_nix_args+=("$1" "${2:-}" "${3:-}")
    shift 3
    ;;
  # Common flake-related options (local only, 2 args)
  --override-input)
    local_nix_args+=("$1" "${2:-}" "${3:-}")
    shift 3
    ;;
  # Common evaluation options (local only, 1 arg)
  --arg-from-stdin | --eval-store | --include | -I)
    local_nix_args+=("$1" "${2:-}")
    shift 2
    ;;
  # Common flake-related options (local only, 1 arg)
  --inputs-from | --output-lock-file | --reference-lock-file | --update-input)
    local_nix_args+=("$1" "${2:-}")
    shift 2
    ;;
  # Common evaluation options (local only, 0 args)
  --debugger | --impure)
    local_nix_args+=("$1")
    shift
    ;;
  # Common flake-related options (local only, 0 args)
  --commit-lock-file | --no-registries | --no-update-lock-file | --no-write-lock-file | --recreate-lock-file)
    local_nix_args+=("$1")
    shift
    ;;
  # Logging options (both local and remote, 1 arg)
  --log-format)
    logging_args+=("$1" "${2:-}")
    shift 2
    ;;
  # Logging options (both local and remote, 0 args)
  --debug | --print-build-logs | -L | --quiet | --verbose | -v)
    logging_args+=("$1")
    shift
    ;;
  -*)
    echo "Warning: Unknown option $1, passing to local nix build"
    local_nix_args+=("$1")
    shift
    ;;
  *)
    installables+=("$1")
    shift
    ;;
  esac
done

# Validate required arguments
if [[ -z "$to_host" ]]; then
  echo "Error: --to username@host is required"
  usage
fi

if [[ ${#installables[@]} -eq 0 ]]; then
  echo "Error: At least one installable is required"
  usage
fi

# Find a free port starting from 5001
serve_port=5001
while lsof -i ":$serve_port" >/dev/null 2>&1; do
  echo "Port $serve_port is in use, trying next port..."
  ((serve_port++))
  if [[ $serve_port -gt 5100 ]]; then
    echo "Error: Could not find a free port between 5001-5100"
    exit 1
  fi
done

echo "Building installables locally: ${installables[*]}"

# BUILD: Build locally and collect store paths
store_paths=()
build_output=$(nom build --no-link --print-out-paths "${local_nix_args[@]}" "${logging_args[@]}" "${installables[@]}" 2>&1)
build_exit=$?

echo "$build_output"

if [[ $build_exit -ne 0 ]]; then
  echo "Error: Local build failed"
  exit $build_exit
fi

while IFS= read -r line; do
  if [[ "$line" =~ ^/nix/store/ ]]; then
    store_paths+=("$line")
  fi
done <<<"$build_output"

if [[ ${#store_paths[@]} -eq 0 ]]; then
  echo "Error: No store paths found in build output"
  exit 1
fi

echo "Built store paths:"
printf '  %s\n' "${store_paths[@]}"

# SERVE: Start nix-serve locally
echo "Starting nix-serve on localhost:$serve_port..."
nix_serve_args=(--listen "127.0.0.1:$serve_port")
# Add --quiet unless verbose logging is requested
if [[ ! " ${logging_args[*]} " =~ " --verbose " ]] && [[ ! " ${logging_args[*]} " =~ " -v " ]] && [[ ! " ${logging_args[*]} " =~ " --debug " ]]; then
  nix_serve_args+=(--quiet)
fi
nix-serve "${nix_serve_args[@]}" &
SERVE_PID=$!

sleep 1

if ! kill -0 "$SERVE_PID" 2>/dev/null; then
  echo "Error: nix-serve failed to start"
  exit 1
fi

echo "nix-serve running (PID: $SERVE_PID)"

# COPY: SSH with reverse port forwarding and run remote nix build
echo "Connecting to $to_host and copying store paths..."

remote_cmd=()

if [[ -n "$remote_user" ]]; then
  remote_cmd+=(sudo -u "$remote_user")
fi

remote_cmd+=(nix build)
remote_cmd+=(--option substituters "http://localhost:$serve_port")

if [[ -n "$no_check_sigs" ]]; then
  remote_cmd+=(--option require-sigs false)
fi

remote_cmd+=("${store_paths[@]}")
remote_cmd+=("${logging_args[@]}")

ssh_cmd=(ssh -t)
ssh_cmd+=(-o ExitOnForwardFailure=yes)
ssh_cmd+=(-R "$serve_port:localhost:$serve_port")
ssh_cmd+=("$to_host")
ssh_cmd+=(-- "${remote_cmd[@]}")

echo "Running: ${ssh_cmd[*]}"

if "${ssh_cmd[@]}"; then
  echo "Successfully copied store paths to $to_host"
  exit 0
else
  echo "Error: Remote build/copy failed"
  exit 1
fi
