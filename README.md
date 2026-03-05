# dotfiles

A fast, clean bash setup for senior developers coming from zsh/oh-my-zsh.  
Focused on **syntax highlighting** and a **minimal, fast prompt** — tuned for TypeScript and Python workflows.

Supports **openSUSE Tumbleweed** and **Ubuntu** (also Pop!_OS, Linux Mint).

## What you get

| Feature | Tool | What it does |
|---|---|---|
| **Syntax highlighting** | [ble.sh](https://github.com/akinomyoga/ble.sh) | Live coloring as you type — green for valid commands, red for typos |
| **Fast prompt** | [Starship](https://starship.rs) | Git branch/status, Python venv, Node version, command duration |
| **Fuzzy finder** | [fzf](https://github.com/junegunn/fzf) | Ctrl+R history search, Ctrl+T file picker, Alt+C directory jump |
| **Better ls** | [eza](https://eza.rocks) | Icons, git status column, tree view |
| **Better cat** | [bat](https://github.com/sharkdp/bat) | Syntax highlighting for file contents |
| **Better grep** | [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast, respects .gitignore |
| **Better find** | [fd](https://github.com/sharkdp/fd) | Fast, intuitive syntax |
| **Better diff** | [delta](https://github.com/dandavison/delta) | Side-by-side git diffs with syntax highlighting |

## Quick start

```bash
git clone https://github.com/YOUR_USER/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
exec bash
```

The installer will:
1. Detect your distro (openSUSE or Ubuntu)
2. Install system packages via `zypper` or `apt`
3. Build and install ble.sh from source
4. Install Starship prompt
5. Symlink all config files (backing up existing ones as `.bak.*`)

Optional: `./install.sh --package-managers` also installs rvm, nvm, and uv.

## Structure

```
dotfiles/
├── install.sh                    # Main installer (distro-aware)
├── uninstall.sh                  # Remove symlinks, restore backups
├── bash/
│   ├── .bashrc                   # Main config (modular, loads everything)
│   ├── .bash_aliases             # Aliases (git, npm, python, docker, etc.)
│   ├── .bash_functions           # Functions (mkcd, fzf helpers, extract, etc.)
│   ├── .blerc                    # ble.sh config (syntax highlighting only)
│   └── .inputrc                  # Readline (tab behavior, key bindings)
├── config/
│   ├── .gitconfig                # Git config with delta integration
│   ├── ripgrep/config            # ripgrep options (smart-case, etc.)
│   └── starship/
│       └── starship.toml         # Prompt config
└── README.md
```

## Key bindings

| Binding | Action |
|---|---|
| `Tab` / `Shift+Tab` | Cycle through completions |
| `↑` / `↓` | History search (filtered by current input) |
| `Ctrl+R` | Fuzzy history search (fzf) |
| `Ctrl+T` | Fuzzy file picker (fzf) |
| `Alt+C` | Fuzzy cd into directory (fzf) |
| `Ctrl+Left/Right` | Move by word |
| `Alt+.` | Insert last argument from previous command |

## Useful aliases

**Git** — `gs` (status), `ga` (add), `gcm "msg"` (commit), `gp` (push), `gl` (pull --rebase), `gd` (diff), `glog` (pretty log)

**Node/TS** — `nr` (npm run), `nd` (npm run dev), `nb` (npm run build), `nx` (npx), `tscheck` (tsc --noEmit)

**Python** — `py` (python3), `activate` (auto-find venv), `pytest`, `pyformat` (black), `pylint`/`pyfix` (ruff)

**Docker** — `dkcu` (compose up), `dkcd` (compose down), `dkcl` (compose logs)

## Useful functions

| Function | Description |
|---|---|
| `mkcd <dir>` | Create directory and cd into it |
| `cdf` | Interactive cd with fzf |
| `fe` | Find and edit file with fzf + bat preview |
| `rgi <pattern>` | Ripgrep + fzf interactive search, opens in editor |
| `gbf` | Interactive git branch switch with fzf |
| `gq [msg]` | Quick git add all + commit (default: "wip") |
| `mkvenv [name]` | Create Python venv and activate it |
| `tsinit [name]` | Scaffold a TypeScript project |
| `extract <file>` | Extract any archive format |
| `serve [port]` | Quick HTTP server |
| `groot` | cd to git repo root |
| `killport <port>` | Kill process on port |
| `portlist <port>` | List processes on port |

## Machine-specific config

Create `~/.bash_local` for anything specific to one machine (env vars, extra PATHs, work-specific aliases). It's sourced automatically and not tracked by git.

```bash
# Example ~/.bash_local
export WORK_API_KEY="..."
alias deploy='...'
```

## Customization

**Colors**: Edit `bash/.blerc` — all colors use hex values (Tokyo Night theme by default).  
**Prompt**: Edit `config/starship/starship.toml` — enable/disable modules, change symbols.  
**Aliases**: Edit `bash/.bash_aliases` — organized by category.

## Uninstall

```bash
cd ~/dotfiles
chmod +x uninstall.sh
./uninstall.sh
```

This removes symlinks and restores backups. System packages are left intact.
