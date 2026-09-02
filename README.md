# dotfiles

A clean, modern **Zsh** setup with **Oh My Zsh** and a custom two-line prompt, tailored for developers.

Supports **Linux (openSUSE Tumbleweed / Ubuntu / Fedora / Raspberry Pi OS)**.

## Features

- **Shell:** Zsh + Oh My Zsh
- **Prompt:** custom two-line PROMPT in `.zshrc` (uses OMZ's `git_prompt_info`; no external prompt manager)
- **Plugins:** `zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-completions`
- **Modern CLI Tools:**
  - [eza](https://eza.rocks) (better `ls`)
  - [bat](https://github.com/sharkdp/bat) (better `cat`)
  - [fzf](https://github.com/junegunn/fzf) (fuzzy finder)
  - [ripgrep](https://github.com/BurntSushi/ripgrep) (better `grep`)
  - [fd](https://github.com/sharkdp/fd) (better `find`)
  - [delta](https://github.com/dandavison/delta) (better `git diff`)
- **Development Managers:** `nvm` (Node), `uv` (Python), `rustup` (Rust)
- **DevOps:** [gh](https://cli.github.com) (GitHub CLI), [terraform](https://www.terraform.io), [aws-cli](https://aws.amazon.com/cli/) v2
- **Containers:** Podman + podman-compose + podman-docker on all Linux targets; Buildah + Distrobox on openSUSE/Fedora (`docker` resolves to Podman via the `podman-docker` shim)

> Note: Zed editor is x86_64-only on Linux and is automatically skipped on ARM (Raspberry Pi).

## Installation

### One-liner (recommended)

```bash
bash <(curl -fsSL https://dot.ai-assisted.dev)
```

The bootstrap script clones the repo to `~/Projects/dotfiles` (override with `DOTFILES_DIR=~/your/path`) and runs `install.sh`. If the repo is already present it pulls the latest changes instead of re-cloning. The short URL is served via CloudFront — see [`terraform/`](terraform/) for the infrastructure.

### Manual installation

Clone the repository to your preferred location (e.g., `~/Projects/dotfiles`):

```bash
git clone https://github.com/kayaman/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
```

#### Native Linux (openSUSE / Ubuntu / Fedora)

Installs the full suite of CLI tools, dev environments, and container engines (Podman + podman-compose + podman-docker, plus Buildah + Distrobox on openSUSE/Fedora).

```bash
bash install.sh
```

#### Raspberry Pi OS (64-bit)

Same installer as native Linux — Pi is detected automatically via `/proc/device-tree/model`. Architecture-specific downloads (e.g. SOPS) and ARM-incompatible tools (Zed) are handled.

```bash
bash install.sh
```

### Selecting components

The installer installs everything by default **except** Claude Code, which is opt-in. Use `--with` / `--without` to override:

```bash
bash install.sh --with claude              # also install the Claude CLI + config
bash install.sh --without podman           # skip Podman and friends
bash install.sh --with claude --without chrome,vscode
bash install.sh --help                     # list all components and their defaults
```

Flags work with the one-liner too: `bash <(curl -fsSL https://dot.ai-assisted.dev) --with claude`. Names may be comma-separated or the flag repeated.

Toggleable components: `omz`, `nvm`, `uv`, `rust`, `sops`, `zed`, `claude` (opt-in), `lefthook`, `gh`, `terraform`, `aws-cli`, `vscode`, `podman`, `alacritty`, `chrome`, `cedilla`, `shell`, `fonts` (JetBrainsMono Nerd Font), `git-config` (git identity from `dotfiles.toml`), `dot-filter` (secret-redaction git filter). To add a new one, register it in `COMPONENT_DEFAULT` in `install.sh`, guard its install step with `run_component <name> <fn>`, and add a presence probe to `component_present`.

### Dry run, health check, uninstall

```bash
bash install.sh --dry-run     # show what a run would install — no sudo, no changes
bash install.sh doctor        # verify an installed machine: components, symlinks, config
bash install.sh --verbose     # echo every command (set -x) for debugging
bash install.sh --uninstall   # remove all stow symlinks; print (don't run) tool removal cmds
```

`doctor` exits non-zero if any enabled component is missing or any stow-managed file doesn't resolve into the repo — CI runs it after every install test. `--uninstall --dry-run` composes: preview removal without touching disk.

### Versions

Tool versions (sops, lefthook, gh, terraform, nvm, nerd-fonts) are pinned at the top of `install.sh` for reproducible installs; [Renovate](https://docs.renovatebot.com) bumps them via PRs validated by the install-test CI matrix (see `.github/renovate.json5` — requires the Renovate GitHub app to be enabled on the repo).

## Structure

```
dotfiles/
├── bootstrap.sh                  # One-liner bootstrap: clones repo and runs the right installer
├── install.sh                    # Installer for Native Linux (openSUSE/Ubuntu/Fedora)
├── stow/                         # Stow packages — each is symlinked into $HOME
│   ├── zsh/                      # .zshrc, .aliases, .functions, .path
│   ├── git/                      # .gitconfig, .gitignore_global
│   ├── ripgrep/                  # .config/ripgrep/config
│   ├── readline/                 # .inputrc
│   ├── tree/                     # .treeglobal (global ignore patterns for tree)
│   ├── kitty/                    # .config/kitty/kitty.conf
│   ├── keyd/                     # .config/keyd/default.conf
│   ├── ghostty/                  # .config/ghostty/config
│   ├── xcompose/                 # .XCompose (cedilla fix on US keyboard)
│   ├── cedilla/                  # .config/environment.d/cedilla.conf (GTK/Qt cedilla input module)
│   ├── tmux/                     # .config/tmux/tmux.conf (prefix: C-a)
│   └── vim/                      # .vimrc
├── snippets/                     # Additional shell scripts auto-sourced by .zshrc
├── claude/                       # Curated ~/.claude config (settings, hooks, skills)
├── scripts/                      # Setup scripts
└── README.md
```

## Customization

- **Snippets**: Add any `.sh` file to the `snippets/` directory, and it will be automatically sourced by `.zshrc`.
- **Aliases**: Edit `stow/zsh/.aliases` for your custom command shortcuts.
- **Functions**: Add reusable functions to `stow/zsh/.functions`.
- **Configuration & Secrets**: Copy `dotfiles.toml.example` to `dotfiles.toml` to manage your Git identity, API tokens, and feature toggles:
  ```bash
  cp dotfiles.toml.example dotfiles.toml
  # Edit dotfiles.toml with your favorite editor
  ```
  **Advanced**: For encrypted secrets, create `dotfiles.sops.toml` and encrypt it using [SOPS](https://github.com/getsops/sops). If present, it will take precedence and securely decrypt values on-the-fly. Values in the `[secrets]` section are automatically exported as environment variables.
- **Environment**: Use `.env` or `.env.sh` (ignored by git) in your home directory for machine-specific secrets and tokens not managed via SOPS.
- **Claude Code config**: A curated slice of `~/.claude` (`settings.json`, `hooks/`, `skills/`) is versioned under `claude/`. After changing your Claude setup, capture it with `./scripts/claude-sync.sh backup` and commit. On a new machine, run the installer with `--with claude` to install the Claude CLI and restore this config automatically (or run `./scripts/claude-sync.sh restore` directly), reinstalling marketplaces and enabled plugins from `settings.json`. Login tokens (`.credentials.json`) are intentionally **not** synced — run `claude` to authenticate.

## The `dot` command

`dot` is a Zsh function (defined in `stow/zsh/.functions`, available after install) that manages the dotfiles repo and its config/secrets. Run `dot help` for the authoritative list — the commands below mirror it.

| Command | Description |
| --- | --- |
| `dot sync [msg]` | Commit local changes, `pull --rebase`, then push |
| `dot push [msg]` | Commit all changes and push to origin |
| `dot pull` | Pull from origin and re-apply stow links |
| `dot status` | `git status` plus ahead/behind origin |
| `dot diff` | Uncommitted diff (staged + unstaged) |
| `dot edit` | Open the dotfiles repo in `$EDITOR` / `code` |
| `dot cd` | `cd` into the dotfiles directory |
| `dot doctor` | Health check: stow links, required tools, filter hook, startup time, `dotfiles.toml` |
| `dot update` | Pull, re-stow every package, then dry-run the installer |
| `dot config get <section.key>` | Read a value from `dotfiles.toml` |
| `dot config list [section]` | List keys in a section (or all sections) |
| `dot config apply` | Export `[secrets]` into the current shell |
| `dot filter-install` | Register the git clean filter on this machine |
| `dot filter-show` | List active `.dotfilter` patterns |
| `dot filter-add <pattern>` | Append an ERE pattern to `.dotfilter` |
| `dot check` | Dry-run: show lines that would be redacted |
| `dot profiler [--raw]` | Profile shell startup time (slowest-first) |

### Secret redaction (`.dotfilter`)

Add ERE patterns (one per line) to `$DOTFILES/.dotfilter`. At `git add` time, lines matching any pattern are replaced with a redaction marker **in the git index only** — working-tree files are never modified, so your real secrets stay usable locally while staying out of commits. Run `dot filter-install` once per machine to activate the filter.

## After Installation

The installer already sets your git identity (when `dotfiles.toml` has a `[git]` section), registers the secret-redaction filter, and installs JetBrainsMono Nerd Font. What's left:

1. Restart your terminal or run `exec zsh`, and select **JetBrainsMono Nerd Font** in your terminal emulator so prompt symbols render.
2. If you haven't yet, create your config and re-run the git identity step:
   ```bash
   cp dotfiles.toml.example dotfiles.toml   # fill in [git] name/email (+ signingkey)
   ./scripts/setup-git.sh                   # interactive; or --non-interactive from the toml
   ```
3. Set up keys and upload them to GitHub (interactive, need a GitHub token):
   ```bash
   ./scripts/setup-ssh-github.sh            # generate/select an SSH key + upload
   ./scripts/setup-gpg-github.sh            # generate/select a GPG key + upload
   ```
4. Verify the machine: `bash install.sh doctor`. Use `dot config apply` to export `[secrets]` into your shell.
