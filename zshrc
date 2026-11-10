# Managed by zshup (https://github.com/exbyte-dev/zshup).
# Changes here are replaced when zshup runs again. Put your own settings in
# ~/.zshrc.local, which is sourced at the end of this file.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# zsh-syntax-highlighting has to stay last.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

# -U keeps PATH free of duplicates, so re-sourcing this file is harmless.
typeset -U path PATH
export PATH="$HOME/.local/bin:$PATH"

venv() {
  local dir="${1:-venv}"
  [[ -d "$dir" ]] || python -m venv "$dir"
  source "$dir/bin/activate"
}

source $ZSH/oh-my-zsh.sh

# fzf keybindings and completion, after Oh My Zsh so they win the keymap.
# fzf 0.48 and newer ship them via --zsh. Older distro builds do not, so fall
# back to whichever files the distro installed.
_zshup_init_fzf() {
  (( $+commands[fzf] )) || return 0

  local version
  version=${${(z)"$(fzf --version 2>/dev/null)"}[1]}

  autoload -Uz is-at-least
  if [[ -n $version ]] && is-at-least 0.48 $version; then
    source <(fzf --zsh) 2>/dev/null && return 0
  fi

  local prefix=${PREFIX:-/usr}
  local brew_prefix=""
  (( $+commands[brew] )) && brew_prefix=$(brew --prefix 2>/dev/null)

  local file
  for file in \
    /usr/share/fzf/key-bindings.zsh \
    /usr/share/fzf/shell/key-bindings.zsh \
    /usr/share/doc/fzf/examples/key-bindings.zsh \
    /usr/share/zsh/site-functions/fzf-key-bindings.zsh \
    $prefix/share/fzf/key-bindings.zsh \
    ${brew_prefix:+$brew_prefix/opt/fzf/shell/key-bindings.zsh} \
    /etc/profile.d/fzf.zsh
  do
    [[ -r $file ]] && { source $file; break }
  done

  for file in \
    /usr/share/fzf/completion.zsh \
    /usr/share/fzf/shell/completion.zsh \
    /usr/share/doc/fzf/examples/completion.zsh \
    $prefix/share/fzf/completion.zsh \
    ${brew_prefix:+$brew_prefix/opt/fzf/shell/completion.zsh}
  do
    [[ -r $file ]] && { source $file; break }
  done
}
_zshup_init_fzf
unset -f _zshup_init_fzf

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
