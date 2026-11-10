#!/usr/bin/env bash
#
# zshup - a one-command zsh setup
# https://github.com/exbyte-dev/zshup
#
# Installs zsh, Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting and fzf,
# then deploys a managed ~/.zshrc. Safe to run more than once.

set -euo pipefail

ZSHUP_VERSION="1.0.0"

# Where to fetch the zshrc template from when the script runs standalone
# (for example piped from curl) instead of out of a local clone.
ZSHUP_REPO="${ZSHUP_REPO:-exbyte-dev/zshup}"
ZSHUP_REF="${ZSHUP_REF:-main}"
ZSHUP_RAW_BASE="${ZSHUP_RAW_BASE:-https://raw.githubusercontent.com/${ZSHUP_REPO}/${ZSHUP_REF}}"
OMZ_INSTALLER_URL="${OMZ_INSTALLER_URL:-https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh}"

OMZ_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}"
PLUGINS_DIR="$ZSH_CUSTOM_DIR/plugins"
ZSHRC="$HOME/.zshrc"

# Command names, which happen to match the package names on every supported
# package manager.
REQUIRED_CMDS=(zsh git curl fzf)

PLUGIN_NAMES=(zsh-autosuggestions zsh-syntax-highlighting)
PLUGIN_URLS=(
  "https://github.com/zsh-users/zsh-autosuggestions.git"
  "https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

ASSUME_YES=0
DO_CHSH=1
DRY_RUN=0
UNINSTALL=0

PLATFORM=""
PLATFORM_NAME=""
PKG_MGR=""
PRIV=(env)
MISSING=()
STEP_NO=0
TMPDIR_ZSHUP=""

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_BLUE="" C_GREEN="" C_YELLOW="" C_RED=""
fi

banner() {
  printf '%s\n' "${C_BOLD}${C_BLUE}zshup${C_RESET} ${C_DIM}v${ZSHUP_VERSION}${C_RESET}"
}

step() {
  STEP_NO=$((STEP_NO + 1))
  printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "[$STEP_NO] $*" "$C_RESET"
}

info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '    %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# Shortens $HOME to ~ for display.
pretty_path() { printf '%s' "${1/#$HOME/\~}"; }

# A result line for something that really happened, so it stays quiet during
# a dry run rather than claiming work that was only printed.
ok_done() { ((DRY_RUN)) || ok "$*"; }

# Echoes a command in dry-run mode, runs it otherwise.
run() {
  if ((DRY_RUN)); then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

# ----------------------------------------------------------------------------
# Usage
# ----------------------------------------------------------------------------

usage() {
  cat <<EOF
${C_BOLD}zshup${C_RESET} v${ZSHUP_VERSION} - one-command zsh setup

Usage:
  install.sh [options]
  curl -fsSL ${ZSHUP_RAW_BASE}/install.sh | bash -s -- [options]

Options:
  -y, --yes        Non-interactive. Assume yes to every prompt.
      --no-chsh    Do not change the default shell.
      --dry-run    Print what would happen, change nothing.
      --uninstall  Restore the most recent ~/.zshrc backup.
  -h, --help       Show this help.
  -V, --version    Print the zshup version.

Environment:
  ZSH_CUSTOM       Oh My Zsh custom dir (default: ~/.oh-my-zsh/custom).
  ZSHUP_REF        Git ref to fetch the zshrc template from (default: main).
  NO_COLOR         Set to disable colored output.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      -y|--yes)    ASSUME_YES=1 ;;
      --no-chsh)   DO_CHSH=0 ;;
      --dry-run)   DRY_RUN=1 ;;
      --uninstall) UNINSTALL=1 ;;
      -h|--help)   usage; exit 0 ;;
      -V|--version) printf '%s\n' "$ZSHUP_VERSION"; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
}

# ----------------------------------------------------------------------------
# Prompting, including when stdin is a pipe (curl | bash)
# ----------------------------------------------------------------------------

# True when we can read an answer from a human: either stdin is a terminal or
# the controlling terminal is reachable, which is the case for curl | bash.
have_tty() {
  [[ -t 0 ]] && return 0
  [[ -e /dev/tty ]] && (exec 3</dev/tty) 2>/dev/null
}

# confirm <question>
confirm() {
  local question="$1" reply=""

  ((ASSUME_YES)) && return 0
  ((DRY_RUN)) && return 0

  if ! have_tty; then
    err "no terminal available to answer \"$question\""
    die "re-run with --yes for non-interactive installs"
  fi

  printf '\n%s? %s%s [Y/n] ' "$C_BOLD" "$question" "$C_RESET"
  if [[ -t 0 ]]; then
    read -r reply || true
  else
    read -r reply </dev/tty || true
  fi

  case "${reply:-y}" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# ----------------------------------------------------------------------------
# Platform detection
# ----------------------------------------------------------------------------

detect_platform() {
  local os
  os="$(uname -s)"

  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *com.termux* ]] ||
     [[ -d /data/data/com.termux ]]; then
    PLATFORM="termux"
    PLATFORM_NAME="Termux"
    PKG_MGR="pkg"
  elif [[ "$os" == "Darwin" ]]; then
    PLATFORM="macos"
    PLATFORM_NAME="macOS $(uname -r)"
    PKG_MGR="brew"
    command -v brew >/dev/null 2>&1 ||
      die "Homebrew not found. Install it from https://brew.sh and re-run."
  elif command -v pacman >/dev/null 2>&1; then
    PLATFORM="arch"
    PLATFORM_NAME="$(os_pretty_name "Arch Linux")"
    PKG_MGR="pacman"
  elif command -v apt-get >/dev/null 2>&1; then
    PLATFORM="debian"
    PLATFORM_NAME="$(os_pretty_name "Debian/Ubuntu")"
    PKG_MGR="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PLATFORM="fedora"
    PLATFORM_NAME="$(os_pretty_name "Fedora")"
    PKG_MGR="dnf"
  else
    die "no supported package manager found (pacman, apt, dnf, pkg, brew)"
  fi
}

os_pretty_name() {
  local fallback="$1" name=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    name="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}")"
  fi
  printf '%s' "${name:-$fallback}"
}

# Builds the command prefix used for package installs. Everything is prefixed
# with env so that "VAR=value cmd" works with and without sudo. Homebrew and
# Termux must never run under sudo.
detect_privilege() {
  PRIV=(env)
  case "$PLATFORM" in
    termux|macos) return ;;
    *) ;;
  esac
  if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    PRIV=(sudo env)
  fi
}

# Only package installs need privilege, so a machine that already has
# everything stays runnable without sudo.
require_privilege() {
  case "$PLATFORM" in
    termux|macos) return 0 ;;
    *) ;;
  esac
  [[ "$(id -u)" -eq 0 ]] && return 0
  command -v sudo >/dev/null 2>&1 && return 0
  die "installing packages needs root: install sudo, or run zshup as root"
}

# sudo for writing to system files, which on macOS is not the same thing as
# the package install prefix.
root_prefix() {
  if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    printf '%s' "sudo"
  fi
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------

# Fills MISSING with the required commands this machine does not have.
collect_missing() {
  local cmd
  MISSING=()
  for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
  done
}

install_packages() {
  collect_missing

  step "Install packages (${PKG_MGR})"

  # Expanding an empty array under set -u fails on the bash 3.2 that macOS
  # ships, so MISSING is only ever read inside this non-empty branch.
  if ((${#MISSING[@]} == 0)); then
    ok "zsh, git, curl and fzf are already installed"
    return
  fi

  info "missing: ${MISSING[*]}"
  require_privilege

  case "$PKG_MGR" in
    pacman)
      run "${PRIV[@]}" pacman -Sy --needed --noconfirm "${MISSING[@]}"
      ;;
    apt)
      # ca-certificates keeps https clones working on bare container images.
      run "${PRIV[@]}" DEBIAN_FRONTEND=noninteractive apt-get update -qq
      run "${PRIV[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends ca-certificates "${MISSING[@]}"
      ;;
    dnf)
      run "${PRIV[@]}" dnf install -y --setopt=install_weak_deps=False \
        ca-certificates "${MISSING[@]}"
      ;;
    pkg)
      run "${PRIV[@]}" pkg install -y "${MISSING[@]}"
      ;;
    brew)
      run "${PRIV[@]}" brew install "${MISSING[@]}"
      ;;
    *)
      die "unsupported package manager: $PKG_MGR"
      ;;
  esac

  ok_done "packages installed"
}

install_omz() {
  step "Install Oh My Zsh"

  if [[ -d "$OMZ_DIR" ]]; then
    if [[ -f "$OMZ_DIR/oh-my-zsh.sh" ]]; then
      ok "already installed at $(pretty_path "$OMZ_DIR")"
      return
    fi
    die "$OMZ_DIR exists but does not look like Oh My Zsh; move it aside"
  fi

  if ((DRY_RUN)); then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" \
      "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh install.sh --unattended"
    return
  fi

  local installer="$TMPDIR_ZSHUP/omz-install.sh"
  local log="$TMPDIR_ZSHUP/omz-install.log"
  curl -fsSL "$OMZ_INSTALLER_URL" -o "$installer" ||
    die "could not download the Oh My Zsh installer"

  local had_zshrc=0
  [[ -e "$ZSHRC" ]] && had_zshrc=1

  info "running the installer unattended"
  if ! RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer" --unattended \
      >"$log" 2>&1; then
    sed 's/^/    /' "$log" >&2
    die "the Oh My Zsh installer failed"
  fi

  [[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] || die "Oh My Zsh did not install cleanly"

  # KEEP_ZSHRC only protects an existing file: with no ~/.zshrc the installer
  # writes its own template anyway. Drop it, since the next step deploys ours
  # and a backup of a file from this same run would be noise.
  if ((had_zshrc == 0)) && [[ -f "$ZSHRC" ]]; then
    rm -f "$ZSHRC"
  fi

  ok_done "installed to $(pretty_path "$OMZ_DIR")"
}

install_plugins() {
  step "Install zsh plugins"

  run mkdir -p "$PLUGINS_DIR"

  local i name url dest
  for i in "${!PLUGIN_NAMES[@]}"; do
    name="${PLUGIN_NAMES[$i]}"
    url="${PLUGIN_URLS[$i]}"
    dest="$PLUGINS_DIR/$name"

    if [[ -d "$dest/.git" ]]; then
      info "updating $name"
      if ((DRY_RUN)); then
        printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" \
          "git -C $dest pull --ff-only"
      elif git -C "$dest" pull --ff-only --quiet 2>/dev/null; then
        ok "$name up to date"
      else
        warn "could not update $name, keeping the existing copy"
      fi
    elif [[ -e "$dest" ]]; then
      warn "$dest exists but is not a git clone, leaving it alone"
    else
      info "cloning $name"
      run git clone --depth 1 --quiet "$url" "$dest"
      ok_done "$name installed"
    fi
  done
}

# Puts the zshrc template in $1, from a local clone when available and from the
# repo otherwise, so that curl | bash works.
fetch_template() {
  local dest="$1" src="${BASH_SOURCE[0]:-$0}" local_template=""

  if [[ -f "$src" ]]; then
    local_template="$(cd -- "$(dirname -- "$src")" && pwd)/zshrc"
  fi

  if [[ -n "$local_template" && -f "$local_template" ]]; then
    info "using the local zshrc template"
    cp -- "$local_template" "$dest"
    return
  fi

  info "downloading the zshrc template from $ZSHUP_RAW_BASE/zshrc"
  curl -fsSL "$ZSHUP_RAW_BASE/zshrc" -o "$dest" ||
    die "could not download the zshrc template"
  [[ -s "$dest" ]] || die "the downloaded zshrc template is empty"
}

# A timestamped backup name, with a counter so that two runs in the same
# second cannot overwrite each other.
backup_path() {
  local base candidate n=0
  base="$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
  candidate="$base"
  while [[ -e "$candidate" ]]; do
    n=$((n + 1))
    candidate="$base.$n"
  done
  printf '%s' "$candidate"
}

deploy_zshrc() {
  step "Deploy ~/.zshrc"

  local template="$TMPDIR_ZSHUP/zshrc"

  fetch_template "$template"

  if [[ -f "$ZSHRC" ]] && cmp -s "$template" "$ZSHRC"; then
    ok "$(pretty_path "$ZSHRC") is already up to date"
    return
  fi

  if [[ -e "$ZSHRC" ]]; then
    local backup
    backup="$(backup_path)"
    info "backing up $(pretty_path "$ZSHRC") to $(basename "$backup")"
    run cp -p -- "$ZSHRC" "$backup"
  fi

  if ((DRY_RUN)); then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "install zshrc to $(pretty_path "$ZSHRC")"
  else
    cp -- "$template" "$ZSHRC"
  fi
  ok_done "$(pretty_path "$ZSHRC") deployed"
}

current_shell() {
  local shell=""
  if command -v getent >/dev/null 2>&1; then
    shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  fi
  printf '%s' "${shell:-${SHELL:-}}"
}

register_shell() {
  local zsh_path="$1"

  [[ "$PLATFORM" == "termux" ]] && return 0
  [[ -f /etc/shells ]] || return 0
  grep -qxF "$zsh_path" /etc/shells && return 0

  info "adding $zsh_path to /etc/shells"
  if ((DRY_RUN)); then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" \
      "echo $zsh_path >> /etc/shells"
    return 0
  fi
  local sudo_cmd
  sudo_cmd="$(root_prefix)"
  printf '%s\n' "$zsh_path" | ${sudo_cmd:+$sudo_cmd} tee -a /etc/shells >/dev/null ||
    warn "could not write to /etc/shells"
}

set_default_shell() {
  step "Set zsh as the default shell"

  if ((DO_CHSH == 0)); then
    info "skipped (--no-chsh)"
    return
  fi

  local zsh_path current
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    if ((DRY_RUN)); then
      printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "chsh -s <zsh>"
      return
    fi
    warn "zsh is not on PATH, cannot change the default shell"
    return
  fi

  current="$(current_shell)"
  if [[ "$current" == */zsh || "$current" == "zsh" ]]; then
    ok "zsh is already the default shell"
    return
  fi

  register_shell "$zsh_path"

  # Termux has no /etc/passwd entry, so its chsh takes a bare shell name.
  local chsh_arg="$zsh_path"
  [[ "$PLATFORM" == "termux" ]] && chsh_arg="zsh"

  if ((DRY_RUN)); then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "chsh -s $chsh_arg"
    return
  fi

  if chsh -s "$chsh_arg" 2>/dev/null; then
    ok "default shell set to zsh, it applies at your next login"
  else
    warn "chsh failed (it often needs your password or a writable /etc/shells)"
    info "run it yourself with: chsh -s $chsh_arg"
  fi
}

# ----------------------------------------------------------------------------
# Uninstall
# ----------------------------------------------------------------------------

newest_backup() {
  local backup
  # Newest by name, which sorts the same as by time for our timestamps.
  for backup in "$ZSHRC".bak.*; do
    [[ -f "$backup" ]] && printf '%s\n' "$backup"
  done | sort | tail -n 1
}

do_uninstall() {
  banner
  step "Restore the previous ~/.zshrc"

  local backup
  backup="$(newest_backup)"

  if [[ -z "$backup" ]]; then
    err "no backup found at ~/.zshrc.bak.*"
    info "nothing to restore, your ~/.zshrc was left untouched"
    exit 1
  fi

  info "most recent backup: $(basename "$backup")"
  if ! confirm "Restore $(basename "$backup") over ~/.zshrc?"; then
    info "cancelled"
    exit 0
  fi

  run cp -p -- "$backup" "$ZSHRC"
  ok_done "$(pretty_path "$ZSHRC") restored from $(basename "$backup")"

  printf '\n'
  info "Oh My Zsh and the plugins were left in place. To remove them too:"
  info "  uninstall_oh_my_zsh      # or: rm -rf $(pretty_path "$OMZ_DIR")"
  info "Backups were kept. Remove them with: rm ~/.zshrc.bak.*"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

plan_summary() {
  collect_missing

  printf '\n'
  info "platform:     $PLATFORM_NAME"
  info "package mgr:  $PKG_MGR"
  if ((${#MISSING[@]})); then
    info "to install:   ${MISSING[*]}"
  else
    info "to install:   nothing, all packages present"
  fi
  info "oh-my-zsh:    $([[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] && echo "present" || echo "will install") ($(pretty_path "$OMZ_DIR"))"
  info "plugins:      ${PLUGIN_NAMES[*]}"
  info "zshrc:        $(pretty_path "$ZSHRC")$([[ -e "$ZSHRC" ]] && echo " (backed up if it changes)" || echo "")"
  if ((DO_CHSH)); then
    info "default shell: zsh"
  else
    info "default shell: unchanged (--no-chsh)"
  fi
}

cleanup() {
  [[ -n "$TMPDIR_ZSHUP" && -d "$TMPDIR_ZSHUP" ]] && rm -rf "$TMPDIR_ZSHUP"
  return 0
}

on_signal() {
  printf '\n'
  err "interrupted"
  exit 130
}

main() {
  parse_args "$@"

  TMPDIR_ZSHUP="$(mktemp -d "${TMPDIR:-/tmp}/zshup.XXXXXX")"
  trap cleanup EXIT
  trap on_signal INT TERM

  if ((UNINSTALL)); then
    do_uninstall
    return
  fi

  banner
  detect_platform
  detect_privilege
  plan_summary

  if ((DRY_RUN)); then
    printf '\n%s%s%s\n' "$C_DIM" "dry run, nothing will be changed" "$C_RESET"
  elif ! confirm "Set up zsh on this machine?"; then
    info "cancelled"
    return
  fi

  install_packages
  install_omz
  install_plugins
  deploy_zshrc
  set_default_shell

  printf '\n%s%sDone.%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  if ((DRY_RUN)); then
    info "that was a dry run, re-run without --dry-run to apply it"
  else
    info "start a new shell, or run: exec zsh"
    info "put your own tweaks in ~/.zshrc.local so updates keep them"
  fi
}

main "$@"
