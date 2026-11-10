# zshup

One command to set up zsh: packages, Oh My Zsh, autosuggestions, syntax
highlighting, fzf keybindings and a managed `~/.zshrc`.

It targets the machines a shell usually has to be rebuilt on: Arch and
EndeavourOS laptops, Debian and Ubuntu servers, Termux on Android, Fedora and
macOS. Running it twice is safe. The second run updates the plugins and changes
nothing else.

The config it deploys is opinionated, not configurable: one theme, three
plugins, a couple of defaults. Everything personal belongs in `~/.zshrc.local`,
which survives updates. See [Customizing](#customizing) to extend it and
[Making it yours](#making-it-yours) to change the defaults themselves.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/exbyte-dev/zshup/main/install.sh | bash
```

Unattended, for provisioning a server:

```sh
curl -fsSL https://raw.githubusercontent.com/exbyte-dev/zshup/main/install.sh | bash -s -- --yes
```

Or from a clone:

```sh
git clone https://github.com/exbyte-dev/zshup.git
cd zshup
./install.sh
```

Needs `bash`, and root or `sudo` if any of the packages are missing. The
one-liner needs `curl` too; from a clone, a missing `curl` is installed in the
first step. On macOS, install [Homebrew](https://brew.sh) first.

Piping into `bash` does not skip the confirmation prompt. The script reads the
answer from `/dev/tty`, so it still works through the one-liner. Where there is
no terminal at all, such as CI or a container build, it stops and asks for
`--yes` rather than guessing.

## What it sets up

1. **Packages**, through whichever package manager is present: `zsh`, `git`,
   `curl`, `fzf`. Anything already installed is left alone.
2. **Oh My Zsh**, installed unattended with `RUNZSH=no CHSH=no KEEP_ZSHRC=yes`
   so it does not switch shells or rewrite any config mid-install.
3. **Plugins**, cloned into `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins`:
   [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and
   [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting).
   On a re-run they are updated with `git pull --ff-only` instead of recloned.
4. **`~/.zshrc`**, from the [`zshrc`](zshrc) template in this repo. An existing
   file is copied to `~/.zshrc.bak.<timestamp>` first.
5. **The default shell**, set to zsh with `chsh` unless it already is.

The deployed `~/.zshrc` is short and readable: the `robbyrussell` theme, the
`git`, `zsh-autosuggestions` and `zsh-syntax-highlighting` plugins (highlighting
last, as it requires), `~/.local/bin` on `PATH` for pipx tools, a
duplicate-free `PATH`, fzf keybindings, and a `venv` helper:

```sh
venv          # create ./venv if missing, then activate it
venv .venv    # same, with a different directory name
```

fzf keybindings come from `fzf --zsh` on fzf 0.48 and newer. Older distro
builds, including the ones on Debian and Ubuntu, do not have that flag, so the
template falls back to the distro's `key-bindings.zsh` and `completion.zsh`
wherever they happen to live. A missing fzf is not an error.

Nothing else is touched: no `~/.zshenv`, no login files, no history migration,
no plugin manager. The one system file it can write to is `/etc/shells`, and
only to add the zsh path when `chsh` would otherwise reject it.

## Options

| Flag | Effect |
| --- | --- |
| `-y`, `--yes` | Non-interactive, assume yes to every prompt. |
| `--no-chsh` | Leave the default shell alone. |
| `--dry-run` | Print every step without changing anything. |
| `--uninstall` | Restore the most recent `~/.zshrc` backup. |
| `-h`, `--help` | Show usage. |
| `-V`, `--version` | Print the version. |

| Variable | Effect |
| --- | --- |
| `ZSH_CUSTOM` | Oh My Zsh custom directory. Default `~/.oh-my-zsh/custom`. |
| `ZSHUP_REPO` | Repo to fetch the zshrc template from. Default `exbyte-dev/zshup`. |
| `ZSHUP_REF` | Git ref to fetch the template from. Default `main`. |
| `NO_COLOR` | Turn off colored output. |

A non-default `ZSH_CUSTOM` has to be exported from `~/.zshenv` as well. The
installer clones the plugins wherever it is pointed, but Oh My Zsh only looks
there if `ZSH_CUSTOM` is set before the shell starts, and `~/.zshrc.local` is
sourced too late for that.

## Supported platforms

| Platform | Package manager | Notes |
| --- | --- | --- |
| Arch and derivatives | `pacman` | |
| Debian, Ubuntu | `apt` | Older fzf, handled by the template |
| Fedora | `dnf` | |
| Termux on Android | `pkg` | `chsh -s zsh`, no `sudo`, no `/etc/shells` |
| macOS | `brew` | Homebrew has to be installed already |

Package installs go through `sudo` when the user is not root. Homebrew and
Termux never run under sudo. If `chsh` fails, which it can when it wants a
password, the run still completes and prints the command to finish by hand.

## Customizing

`~/.zshrc` is a managed file and gets replaced on the next run. Personal
settings go in `~/.zshrc.local`, which the template sources at the very end:

```sh
cat >> ~/.zshrc.local <<'EOF'
alias gs='git status -sb'
export EDITOR=nvim
EOF
```

The installer never creates or modifies that file. The managed `~/.zshrc` only
sources it, if it exists.

## Making it yours

Different theme, other plugins, more defaults: fork the repo and edit
[`zshrc`](zshrc). Running `./install.sh` from a clone always deploys the
template sitting next to it, so a fork needs no further changes to work locally.

For the one-liner to serve a fork's template, point the script at it, since the
repo name is a default inside `install.sh` rather than something it can infer
when piped:

```sh
curl -fsSL https://raw.githubusercontent.com/you/zshup/main/install.sh |
  ZSHUP_REPO=you/zshup bash -s -- --yes
```

Or edit the `ZSHUP_REPO` default at the top of `install.sh` once, in the fork.

## Uninstall

```sh
./install.sh --uninstall
```

This copies the most recent `~/.zshrc.bak.<timestamp>` back over `~/.zshrc`. It
keeps the backup files and leaves Oh My Zsh and the plugins in place. To remove
those too:

```sh
uninstall_oh_my_zsh      # or: rm -rf ~/.oh-my-zsh
rm ~/.zshrc.bak.*        # once the backups are no longer wanted
chsh -s "$(command -v bash)"
```

## Testing

[`tests/docker-test.sh`](tests/docker-test.sh) runs the installer twice in
`debian`, `ubuntu`, `fedora` and `archlinux` containers, as an unprivileged user
with sudo, and checks that the second run changes nothing. It needs Docker:

```sh
tests/docker-test.sh              # all four images
tests/docker-test.sh debian       # just one
```

Each container checks the full path: that a dry run changes nothing, that no
terminal plus no `--yes` is refused, that the plugins and the zshrc land, that
an interactive zsh starts clean with the theme, plugins, `PATH` and fzf
keybindings in place, that a second run takes no backup and reclones nothing,
and that `--uninstall` restores the previous file.

`install.sh` runs under `set -euo pipefail` and is `shellcheck` clean.

## License

[MIT](LICENSE)
