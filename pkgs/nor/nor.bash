#!/usr/bin/env bash

show_help() {
  SOURCE_DATE_EPOCH=1 man @mandir@/nor.1*
}

usage() {
  echo "Usage: nor [OPTIONS] [INSTALLABLE] [-- ARG...]"
  echo "Try 'nor --help' for more information."
}

# Parse custom arguments
pname=""
target_host=""
copy_to_host=""
sudo_prefix=""
use_nix_copy_as=""
trusted_user=""
no_check_sigs=""
nix_build_args=()
run_args=()

# Check if nom is available, fallback to nix
nix="nom"
if ! command -v "$nix" &>/dev/null; then
  nix="nix"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  --pname)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --pname requires a value" >&2
      usage >&2
      exit 1
    fi
    pname="$2"
    shift 2
    ;;
  --target-host)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --target-host requires a value" >&2
      usage >&2
      exit 1
    fi
    target_host="$2"
    shift 2
    ;;
  --copy-to)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --copy-to requires a value" >&2
      usage >&2
      exit 1
    fi
    copy_to_host="$2"
    shift 2
    ;;
  --sudo)
    sudo_prefix="sudo"
    shift
    ;;
  --as)
    use_nix_copy_as="yes"
    shift
    ;;
  --trusted-user)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --trusted-user requires a value" >&2
      usage >&2
      exit 1
    fi
    trusted_user="$2"
    use_nix_copy_as="yes"
    shift 2
    ;;
  --no-check-sigs)
    no_check_sigs="yes"
    use_nix_copy_as="yes"
    shift
    ;;
  --help)
    show_help
    exit 0
    ;;
  --)
    # Everything after -- goes to run_args
    shift
    run_args=("$@")
    break
    ;;
  *)
    nix_build_args+=("$1")
    shift
    ;;
  esac
done

# BUILD: Run nix build and get the result path
echo "Running $nix build --no-link --print-out-paths ${nix_build_args[*]}"
build_output=$("$nix" build --no-link --print-out-paths "${nix_build_args[@]}")
build_exit_code=$?

echo "$build_output"

if [[ $build_exit_code -ne 0 ]]; then
  echo "Error: $nix build failed with exit code $build_exit_code"
  exit $build_exit_code
fi

build_result=$(echo "$build_output" | tail -n1 | grep -E '^/nix/store/' | tr -d '[:space:]')

if [[ -z "$build_result" ]]; then
  echo "Error: Could not determine build result path from $nix build output"
  exit 1
fi

# COPY: Copy build result to remote host(s) if needed
copy_to_host="${copy_to_host:-"$target_host"}"

if [[ -n "$copy_to_host" ]]; then
  echo "Copying $build_result to $copy_to_host"

  if [[ -n "$use_nix_copy_as" ]]; then
    copy_cmd=(nix-copy-as --to "$copy_to_host")

    if [[ -n "$trusted_user" ]]; then
      copy_cmd+=(--trusted-user "$trusted_user")
    fi

    if [[ -n "$no_check_sigs" ]]; then
      copy_cmd+=(--no-check-sigs)
    fi

    copy_cmd+=("$build_result")

    if ! "${copy_cmd[@]}"; then
      echo "Error: Failed to copy build result to $copy_to_host"
      exit 1
    fi
  else
    if ! nix copy --to "ssh://$copy_to_host" "$build_result"; then
      echo "Error: Failed to copy build result to $copy_to_host"
      exit 1
    fi
  fi

  if [[ -z "$target_host" ]]; then
    echo "Copied build result, not executing."
    exit 0
  fi
fi

# PREPARE: Determine what executable to run
if [[ -n "$pname" ]]; then
  execute_path="$build_result/bin/$pname"
  if [[ ! -x "$execute_path" ]]; then
    echo "Error: Could not find executable '$pname' in $build_result/bin/"
    exit 1
  fi
else
  main_program=$(nix derivation show "$build_result" 2>/dev/null | jq -r '.derivations | to_entries[0].value.env | .NIX_MAIN_PROGRAM // .name // empty' 2>/dev/null)

  if [[ -n "$main_program" && -x "$build_result/bin/$main_program" ]]; then
    pname="$main_program"
    execute_path="$build_result/bin/$pname"
  elif [[ -x "$build_result" ]]; then
    execute_path="$build_result"
  else
    echo "Error: Could not determine executable to run. Please specify with --pname"
    echo "The build result does not have a NIX_MAIN_PROGRAM attribute and is not an executable file."
    exit 1
  fi
fi

# EXECUTE: Run the executable with any arguments
run_cmd=()
if [[ -n "$sudo_prefix" ]]; then
  run_cmd+=("$sudo_prefix")
fi
run_cmd+=("$execute_path" "${run_args[@]}")

echo "Command: ${run_cmd[*]}"

if [[ -n "$target_host" ]]; then
  echo "Executing on $target_host"
  ssh -t "$target_host" -- "${run_cmd[@]}"
else
  echo "Executing locally"
  "${run_cmd[@]}"
fi
