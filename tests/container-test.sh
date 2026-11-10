#!/usr/bin/env bash
#
# Runs inside a container, as root. Creates an unprivileged user with sudo,
# then exercises install.sh: dry run, install, a second install to check
# idempotency, and uninstall. Driven by tests/docker-test.sh, it is not meant
# to be run on your own machine.

set -euo pipefail

USER_NAME="tester"
REPO="/repo"

C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_RESET=$'\033[0m'

phase() { printf '\n%s### %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
pass()  { printf '  %sok%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
fail()  { printf '  %sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# check <label> <command...>
check() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

# as_user <command string>
as_user() {
  su - "$USER_NAME" -s /bin/bash -c "$1"
}

# fedora:latest ships no diffutils, so cmp is not available to compare with.
same_file() {
  [[ -f "$1" && -f "$2" ]] || return 1
  [[ "$(wc -c <"$1")" == "$(wc -c <"$2")" ]] || return 1
  [[ "$(cat -- "$1")" == "$(cat -- "$2")" ]]
}

home() { getent passwd "$USER_NAME" | cut -d: -f6; }
login_shell() { getent passwd "$USER_NAME" | cut -d: -f7; }
count_backups() { find "$(home)" -maxdepth 1 -name '.zshrc.bak.*' | wc -l | tr -d ' '; }

# Tracks the files zshup is responsible for, to prove a second run adds none.
fingerprint() {
  find "$(home)" -maxdepth 5 \( -name '.git' -o -name '.zshrc*' \) | sort
}

# ----------------------------------------------------------------------------
# Bootstrap: sudo, an unprivileged user, and a working chsh
# ----------------------------------------------------------------------------

bootstrap() {
  phase "bootstrap"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends sudo passwd >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    # chsh lives in util-linux-user on Fedora and is not in the base image.
    dnf install -y -q sudo shadow-utils util-linux-user >/dev/null
  elif command -v pacman >/dev/null 2>&1; then
    # A full upgrade, because -Sy alone against the image's stale database
    # cannot satisfy dependencies. A throwaway container can afford it.
    pacman -Syu --noconfirm --needed sudo >/dev/null
  else
    fail "no supported package manager in this image"
  fi

  id "$USER_NAME" >/dev/null 2>&1 || useradd -m -s /bin/bash "$USER_NAME"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER_NAME" >"/etc/sudoers.d/$USER_NAME"
  chmod 0440 "/etc/sudoers.d/$USER_NAME"

  # chsh authenticates through PAM, and this account has no password to
  # authenticate with, so an unprivileged chsh would fail for a reason that has
  # nothing to do with zshup. A real user has a password here.
  cat >/etc/pam.d/chsh <<'PAM'
auth       sufficient   pam_permit.so
account    sufficient   pam_permit.so
password   required     pam_permit.so
session    required     pam_permit.so
PAM
  pass "user $USER_NAME created with passwordless sudo and chsh"
}

# ----------------------------------------------------------------------------
# Phases
# ----------------------------------------------------------------------------

test_no_tty_needs_yes() {
  phase "piped with no tty and no --yes"

  local out="" status=0
  out="$(as_user "$REPO/install.sh </dev/null 2>&1")" || status=$?

  if ((status == 0)); then
    printf '%s\n' "$out"
    fail "it should have refused to run with no tty and no --yes"
  fi
  case "$out" in
    *--yes*) pass "refused and pointed at --yes" ;;
    *) printf '%s\n' "$out"; fail "refused without mentioning --yes" ;;
  esac
  check "nothing was created" [ ! -e "$(home)/.oh-my-zsh" ]
}

test_dry_run() {
  phase "dry run on a clean home"

  as_user "$REPO/install.sh --dry-run"
  check "no ~/.zshrc created"      [ ! -e "$(home)/.zshrc" ]
  check "no ~/.oh-my-zsh created"  [ ! -e "$(home)/.oh-my-zsh" ]
  check "no packages installed"    [ ! -x /usr/bin/zsh ]
  check "login shell untouched"    [ "$(login_shell)" = "/bin/bash" ]
}

test_install() {
  phase "first install"

  as_user "$REPO/install.sh --yes"

  local h
  h="$(home)"
  check "oh-my-zsh installed"        [ -f "$h/.oh-my-zsh/oh-my-zsh.sh" ]
  check "autosuggestions cloned"     [ -d "$h/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git" ]
  check "syntax highlighting cloned" [ -d "$h/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git" ]
  check "zshrc matches the template" same_file "$REPO/zshrc" "$h/.zshrc"
  check "no spurious backup"         [ "$(count_backups)" = "0" ]
  check "zsh is the login shell"     [ "$(login_shell)" = "$(command -v zsh)" ]
  check "zsh is listed in /etc/shells" grep -qxF "$(command -v zsh)" /etc/shells
}

test_shell_loads() {
  phase "the deployed zshrc works"

  # fzf's own key-bindings.zsh saves and restores shell options, and the zle
  # option cannot be restored in a shell with no terminal, which is what
  # "zsh -i -c" is. That message is an artifact of the test, not of the zshrc,
  # so it is the one line allowed on stderr.
  local stderr_out
  stderr_out="$(as_user "zsh -i -c 'exit 0'" 2>&1 >/dev/null |
    grep -v "can't change option: zle" || true)"
  if [[ -n "$stderr_out" ]]; then
    printf '%s\n' "$stderr_out" | sed 's/^/  | /'
    fail "an interactive zsh printed errors"
  fi
  pass "an interactive zsh starts with no errors"

  check "venv helper is defined" \
    as_user "zsh -i -c 'typeset -f venv >/dev/null'"
  check "autosuggestions loaded" \
    as_user "zsh -i -c '[[ -n \$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE ]]'"
  check "syntax highlighting loaded" \
    as_user "zsh -i -c '[[ -n \${ZSH_HIGHLIGHT_HIGHLIGHTERS[1]} ]]'"
  check "theme applied" \
    as_user "zsh -i -c '[[ \$ZSH_THEME == robbyrussell ]]'"
  check "PATH starts with the local bin dir" \
    as_user "zsh -i -c '[[ \${path[1]} == \$HOME/.local/bin ]]'"
  check "PATH has no duplicates after sourcing the zshrc again" \
    as_user "zsh -i -c 'source ~/.zshrc; typeset -a u; u=(\${(u)path}); (( \$#path == \$#u ))'"

  # fzf 0.48 and newer provide the keybindings through --zsh, older distro
  # builds through a shipped key-bindings.zsh. Either way ctrl-r has to land
  # on an fzf widget.
  local bindkey_out
  bindkey_out="$(as_user "zsh -i -c 'bindkey \"^R\"'" 2>/dev/null || true)"
  printf '  fzf %s, ctrl-r is %s\n' \
    "$(fzf --version 2>/dev/null || echo missing)" "$bindkey_out"
  case "$bindkey_out" in
    *fzf*) pass "ctrl-r is bound to an fzf widget" ;;
    *) fail "ctrl-r is not bound to fzf" ;;
  esac

  as_user "printf 'export ZSHUP_LOCAL_OK=1\n' > ~/.zshrc.local"
  local local_out
  local_out="$(as_user "zsh -i -c 'printf %s \$ZSHUP_LOCAL_OK'" 2>/dev/null || true)"
  check "zshrc.local is sourced" [ "$local_out" = "1" ]
}

test_idempotency() {
  phase "second install, nothing should change"

  local h before after out
  h="$(home)"
  before="$(fingerprint)"

  out="$(as_user "$REPO/install.sh --yes" 2>&1)"
  printf '%s\n' "$out" | sed 's/^/  | /'

  after="$(fingerprint)"

  check "no new files or clones" [ "$before" = "$after" ]
  check "no new backup"          [ "$(count_backups)" = "0" ]
  check "zshrc still matches the template" same_file "$REPO/zshrc" "$h/.zshrc"

  case "$out" in
    *"already up to date"*) pass "left the zshrc alone" ;;
    *) fail "did not report the zshrc as up to date" ;;
  esac
  case "$out" in
    *"already the default shell"*) pass "skipped chsh" ;;
    *) fail "did not skip chsh" ;;
  esac
  case "$out" in
    *cloning*) fail "recloned a plugin" ;;
    *) pass "updated the plugins instead of recloning" ;;
  esac
  case "$out" in
    *"already installed"*) pass "kept the existing oh-my-zsh" ;;
    *) fail "did not detect the existing oh-my-zsh" ;;
  esac
}

test_backup_and_uninstall() {
  phase "backup and uninstall"

  local h
  h="$(home)"
  as_user "printf '# my own zshrc\n' > ~/.zshrc"

  as_user "$REPO/install.sh --yes" >/dev/null
  check "a backup was taken"            [ "$(count_backups)" = "1" ]
  check "the managed zshrc is in place" same_file "$REPO/zshrc" "$h/.zshrc"

  as_user "$REPO/install.sh --uninstall --yes"
  check "the old zshrc came back" [ "$(cat "$h/.zshrc")" = "# my own zshrc" ]
  check "oh-my-zsh was left alone" [ -f "$h/.oh-my-zsh/oh-my-zsh.sh" ]
  check "the backup was kept"      [ "$(count_backups)" = "1" ]
}

main() {
  bootstrap
  test_no_tty_needs_yes
  test_dry_run
  test_install
  test_shell_loads
  test_idempotency
  test_backup_and_uninstall

  printf '\n%sall checks passed%s\n' "$C_GREEN" "$C_RESET"
}

main "$@"
