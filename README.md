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
- **Development Managers:** `nvm` (Node), `pyenv` (Python), `uv` (Python), `rustup` (Rust)
- **DevOps:** [gh](https://cli.github.com) (GitHub CLI), [terraform](https://www.terraform.io)
- **Containers:** Podman + Buildah + Distrobox on all Linux targets; Docker only on openSUSE/Ubuntu (Fedora uses Podman)

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

Installs the full suite of CLI tools, dev environments, and container engines (Podman + Buildah + Distrobox; Docker on openSUSE/Ubuntu).

```bash
bash install.sh
```

#### Raspberry Pi OS (64-bit)

Same installer as native Linux — Pi is detected automatically via `/proc/device-tree/model`. Architecture-specific downloads (e.g. SOPS) and ARM-incompatible tools (Zed) are handled.

```bash
bash install.sh
```

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

## After Installation

1. Restart your terminal or run `exec zsh`.
2. Configure your favorite terminal emulator to use a **Nerd Font** (e.g., JetBrains Mono Nerd Font) to correctly render prompt symbols.
3. Configure your Git user and GPG signing preferences by running:
   ```bash
   ./scripts/setup-git.sh
   ```
