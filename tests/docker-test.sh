#!/usr/bin/env bash
#
# Runs the installer twice in a set of containers to check that it works on
# each distro and that a second run changes nothing.
#
#   tests/docker-test.sh             # every image
#   tests/docker-test.sh debian      # one image, by name or by tag

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

DEFAULT_IMAGES=(
  debian:stable-slim
  ubuntu:latest
  fedora:latest
  archlinux:latest
)

C_BOLD=$'\033[1m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_RESET=$'\033[0m'

DOCKER="${DOCKER:-docker}"
command -v "$DOCKER" >/dev/null 2>&1 || {
  printf 'error: %s not found\n' "$DOCKER" >&2
  exit 1
}

images=()
if (($# > 0)); then
  for arg in "$@"; do
    case "$arg" in
      *:*) images+=("$arg") ;;
      debian) images+=(debian:stable-slim) ;;
      *) images+=("$arg:latest") ;;
    esac
  done
else
  images=("${DEFAULT_IMAGES[@]}")
fi

failed=()
for image in "${images[@]}"; do
  printf '\n%s===========================================================%s\n' \
    "$C_BOLD" "$C_RESET"
  printf '%s  %s%s\n' "$C_BOLD" "$image" "$C_RESET"
  printf '%s===========================================================%s\n' \
    "$C_BOLD" "$C_RESET"

  if "$DOCKER" run --rm \
      -v "$REPO_ROOT:/repo:ro" \
      -e TERM=dumb \
      "$image" \
      /bin/bash /repo/tests/container-test.sh; then
    printf '%s%s passed%s\n' "$C_GREEN" "$image" "$C_RESET"
  else
    printf '%s%s failed%s\n' "$C_RED" "$image" "$C_RESET"
    failed+=("$image")
  fi
done

printf '\n%ssummary%s\n' "$C_BOLD" "$C_RESET"
for image in "${images[@]}"; do
  case " ${failed[*]-} " in
    *" $image "*) printf '  %sfail%s %s\n' "$C_RED" "$C_RESET" "$image" ;;
    *) printf '  %spass%s %s\n' "$C_GREEN" "$C_RESET" "$image" ;;
  esac
done

((${#failed[@]} == 0)) || exit 1
