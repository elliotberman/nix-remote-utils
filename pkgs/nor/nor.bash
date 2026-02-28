#!/usr/bin/env bash

usage() {
  cat <<EOF
nor - A wrapper around "nom build" that also runs the resulting output

Usage: nor [--pname NAME] [--target-host HOST] [--copy-to HOST] [--sudo] [--as] [--user USER] [--no-check-sigs] [NOM_BUILD_ARGS] -- [RUN_ARGS]

Arguments:
  --pname NAME       Specify the package name to run. If not specified,
                    falls back to nix run behavior.
  --target-host HOST Copy the result to the specified remote host and run it there.
  --copy-to HOST     Copy the result to the specified remote host (defaults to target-host if specified).
                    If only --copy-to is specified (no --target-host), will only copy and not execute.
  --sudo            Run the command with sudo
  --as              Use nix-copy-as instead of nix copy for copying
  --user USER       Remote username for nix-copy-as (implies --as)
  --no-check-sigs   Disable signature checking with nix-copy-as (implies --as)
  NOM_BUILD_ARGS     Arguments passed directly to "nom build"
  -- RUN_ARGS        Arguments passed to the executable after --

Example:
  nor --pname hello -- --version            # Build and run locally
  nor --target-host server1 --pname my-tool # Build, copy to server1, and run on server1
  nor --copy-to server1 --pname my-tool     # Just copy to server1, don't execute
  nor --sudo ./default.nix -- arg1 arg2     # Build and run locally with sudo
  nor --as --copy-to server1 --pname my-tool # Copy using nix-copy-as
  nor --user alice --copy-to server1 --pname my-tool # Copy as user alice
EOF
  exit 1
}

# Parse custom arguments
pname=""
target_host=""
copy_to_host=""
sudo_prefix=""
use_nix_copy_as=""
remote_user=""
no_check_sigs=""
nom_build_args=()
run_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --pname)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --pname requires a value"
      usage
    fi
    pname="$2"
    shift 2
    ;;
  --target-host)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --target-host requires a value"
      usage
    fi
    target_host="$2"
    shift 2
    ;;
  --copy-to)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --copy-to requires a value"
      usage
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
  --user)
    if [[ -z "$2" || "$2" == --* ]]; then
      echo "Error: --user requires a value"
      usage
    fi
    remote_user="$2"
    use_nix_copy_as="yes"
    shift 2
    ;;
  --no-check-sigs)
    no_check_sigs="yes"
    use_nix_copy_as="yes"
    shift
    ;;
  --help)
    usage
    ;;
  --)
    # Everything after -- goes to run_args
    shift
    run_args=("$@")
    break
    ;;
  *)
    nom_build_args+=("$1")
    shift
    ;;
  esac
done

# BUILD: Run nom build and get the result path
echo "Running nom build --no-link --print-out-paths ${nom_build_args[*]}"
build_output=$(nom build --no-link --print-out-paths "${nom_build_args[@]}")
build_exit_code=$?

echo "$build_output"

if [[ $build_exit_code -ne 0 ]]; then
  echo "Error: nom build failed with exit code $build_exit_code"
  exit $build_exit_code
fi

build_result=$(echo "$build_output" | tail -n1 | grep -E '^/nix/store/' | tr -d '[:space:]')

if [[ -z "$build_result" ]]; then
  echo "Error: Could not determine build result path from nom build output"
  exit 1
fi

# COPY: Copy build result to remote host(s) if needed
copy_to_host="${copy_to_host:-"$target_host"}"

if [[ -n "$copy_to_host" ]]; then
  echo "Copying $build_result to $copy_to_host"

  if [[ -n "$use_nix_copy_as" ]]; then
    copy_cmd=(nix-copy-as --to "$copy_to_host")

    if [[ -n "$remote_user" ]]; then
      copy_cmd+=(--user "$remote_user")
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
