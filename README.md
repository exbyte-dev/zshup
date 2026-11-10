# zshup

A one-command zsh setup. Run it on a fresh machine and you get the same shell
you had on the last one: zsh, Oh My Zsh, autosuggestions, syntax highlighting
and fzf keybindings, with a managed `~/.zshrc`.

It is safe to run again. A second run updates the plugins and leaves everything
else as it was.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/exbyte-dev/zshup/main/install.sh | bash
```

Non-interactive, for provisioning a VPS:

```sh
curl -fsSL https://raw.githubusercontent.com/exbyte-dev/zshup/main/install.sh | bash -s -- --yes
```

Or from a clone:

```sh
git clone https://github.com/exbyte-dev/zshup.git
cd zshup
./install.sh
```

When piped, the script still asks for confirmation by reading your terminal
directly through `/dev/tty`. If there is no terminal at all, such as in CI or a
container build, pass `--yes`.

## What it sets up

1. **Packages**, through whichever package manager the machine has: `zsh`,
   `git`, `curl`, `fzf`. Already-installed packages are skipped.
2. **Oh My Zsh**, installed unattended with `RUNZSH=no CHSH=no KEEP_ZSHRC=yes`
   so it does not take over your shell or your config mid-install.
3. **Plugins**, cloned into `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins`:
   [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and
   [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting).
   On a re-run they are updated with `git pull --ff-only` instead of recloned.
4. **`~/.zshrc`**, from the [`zshrc`](zshrc) template in this repo. Any existing
   file is copied to `~/.zshrc.bak.<timestamp>` first.
5. **The default shell**, set to zsh with `chsh` unless it already is.

The deployed `~/.zshrc` gives you the `robbyrussell` theme, the `git`,
`zsh-autosuggestions` and `zsh-syntax-highlighting` plugins (highlighting last,
as it requires), `~/.local/bin` on `PATH` for pipx tools, a duplicate-free
`PATH`, fzf keybindings, and a `venv` helper:

```sh
venv          # create ./venv if missing, then activate it
venv .venv    # same, with a different directory name
```

fzf keybindings come from `fzf --zsh` on fzf 0.48 and newer. Older distro builds
of fzf, such as the one on Debian and Ubuntu, do not have that flag, so the
template sources the distro's `key-bindings.zsh` and `completion.zsh` instead.
If fzf is missing entirely, nothing errors.

## Options

| Flag | Effect |
| --- | --- |
| `-y`, `--yes` | Non-interactive, assume yes to every prompt. |
| `--no-chsh` | Leave the default shell alone. |
| `--dry-run` | Print every step without changing anything. |
| `--uninstall` | Restore the most recent `~/.zshrc` backup. |
| `-h`, `--help` | Show usage. |
| `-V`, `--version` | Print the version. |

Environment variables: `ZSH_CUSTOM` to relocate the Oh My Zsh custom directory,
`ZSHUP_REF` to pull the zshrc template from a different git ref, `NO_COLOR` to
turn off colored output.

If you do use a non-default `ZSH_CUSTOM`, export it from `~/.zshenv` as well.
The installer clones the plugins wherever you point it, but Oh My Zsh only
looks there if `ZSH_CUSTOM` is already set when your shell starts, and
`~/.zshrc.local` is sourced too late for that.

## Supported platforms

| Platform | Package manager | Notes |
| --- | --- | --- |
| Arch, EndeavourOS | `pacman` | |
| Debian, Ubuntu | `apt` | fzf predates `--zsh`, handled by the template |
| Fedora | `dnf` | |
| Termux on Android | `pkg` | `chsh -s zsh`, no `sudo`, no `/etc/shells` |
| macOS | `brew` | Homebrew has to be installed already |

Package installs use `sudo` when you are not root. Termux and Homebrew installs
never do.

## Customizing

Do not edit `~/.zshrc`, since zshup overwrites it on the next run. Put your own
settings in `~/.zshrc.local`, which the template sources at the very end:

```sh
cat >> ~/.zshrc.local <<'EOF'
alias gs='git status -sb'
export EDITOR=nvim
EOF
```

That file is yours. zshup never writes to it or reads it.

## Uninstall

```sh
./install.sh --uninstall
```

This copies the most recent `~/.zshrc.bak.<timestamp>` back over `~/.zshrc`. It
keeps the backup files, and it leaves Oh My Zsh and the plugins in place. To
remove those too:

```sh
uninstall_oh_my_zsh      # or: rm -rf ~/.oh-my-zsh
rm ~/.zshrc.bak.*        # once you are sure you do not need them
chsh -s "$(command -v bash)"
```

## Testing

[`tests/docker-test.sh`](tests/docker-test.sh) runs the installer twice in
`debian`, `ubuntu`, `fedora` and `archlinux` containers, as an unprivileged user
with sudo, and checks that the second run changes nothing:

```sh
tests/docker-test.sh              # all four images
tests/docker-test.sh debian       # just one
```

`install.sh` is `shellcheck` clean and runs under `set -euo pipefail`.

## License

[MIT](LICENSE)
