# dotfiles

A clean, modern **Zsh** setup with **Oh My Zsh** and **Starship** prompt, tailored for developers.

Supports **Linux (openSUSE Tumbleweed / Ubuntu)** and **WSL**.

## Features

- **Shell:** Zsh + Oh My Zsh
- **Prompt:** [Starship](https://starship.rs)
- **Plugins:** `zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-completions`
- **Modern CLI Tools:**
  - [eza](https://eza.rocks) (better `ls`)
  - [bat](https://github.com/sharkdp/bat) (better `cat`)
  - [fzf](https://github.com/junegunn/fzf) (fuzzy finder)
  - [ripgrep](https://github.com/BurntSushi/ripgrep) (better `grep`)
  - [fd](https://github.com/sharkdp/fd) (better `find`)
  - [delta](https://github.com/dandavison/delta) (better `git diff`)
- **Development Managers:** `nvm` (Node), `pyenv` (Python), `uv` (Python), `rustup` (Rust)
- **Containers:** Podman, Buildah, Distrobox, Docker (on Native Linux)

## Installation

Clone the repository to your preferred location (e.g., `~/Projects/dotfiles`):

```bash
git clone https://github.com/YOUR_USER/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
```

### Native Linux (openSUSE / Ubuntu)

Installs the full suite of CLI tools, dev environments, and container engines (Podman & Docker).

```bash
chmod +x install.sh
./install.sh
```

### WSL (Windows Subsystem for Linux)

A slimmer installation for WSL environments (e.g., Ubuntu/Debian on WSL). Skips desktop-specific components and container daemons.

```bash
chmod +x wsl/install.sh
./wsl/install.sh
```

## Structure

```
dotfiles/
├── install.sh                    # Main installer for Native Linux (openSUSE/Ubuntu)
├── wsl/
│   └── install.sh                # Dedicated installer for WSL
├── .zshrc                        # Main Zsh configuration
├── .aliases                      # Custom shell aliases
├── .functions                    # Custom shell functions
├── .path                         # Environment PATH variables
├── snippets/                     # Additional shell scripts auto-sourced by .zshrc
├── config/                       # Configuration for various tools
│   ├── starship/starship.toml    # Starship prompt configuration
│   ├── ripgrep/config            # Ripgrep configuration
│   ├── kitty/kitty.conf          # Kitty terminal configuration
│   ├── ghostty/config            # Ghostty terminal configuration
│   ├── keyd/default.conf         # Keyd configuration
│   ├── .gitconfig                # Global Git configuration
│   └── .treeglobal               # Tree configuration
└── README.md
```

## Customization

- **Snippets**: Add any `.sh` file to the `snippets/` directory, and it will be automatically sourced by `.zshrc`.
- **Aliases**: Edit `.aliases` for your custom command shortcuts.
- **Functions**: Add reusable functions to `.functions`.
- **Environment**: Use `.env` or `.env.sh` (ignored by git) in your home directory for machine-specific secrets and tokens.

## After Installation

1. Restart your terminal or run `exec zsh`.
2. Configure your favorite terminal emulator to use a **Nerd Font** (e.g., JetBrains Mono Nerd Font) to correctly render Starship prompt symbols.