# snippets/

Shell fragments that are auto-sourced by `.zshrc` at startup.

## How it works

`.zshrc` walks `$DOTFILES/snippets/*.sh` in filesystem (alphabetical) order and
`source`s each readable file. There is no dependency ordering — if one snippet
needs something from another, rename it to sort later (e.g. `00-foo.sh`).

## What belongs here

Small, optional setup logic that doesn't fit in `.functions`, `.path`, or `.aliases`:

- `config.sh` — TOML / SOPS reader that powers `dot config`.
- `cedilla.sh` — GTK/Qt input-method env vars for ç on US keyboards.

## What does NOT belong here

- Tool-specific lazy loaders (Bun, NVM, GCloud, etc.) — they live in `.zshrc`
  next to the other external-tool wiring, so the startup profiler (`dot
  profiler`) can attribute their cost cleanly.
- Function definitions — add to `stow/zsh/.functions.d/` instead.
- Aliases — add to `stow/zsh/.aliases`.

## Adding a snippet

Drop a new `*.sh` file in this directory. It will be sourced on the next shell
start. Keep it small; large snippets should become topic files under
`stow/zsh/.functions.d/`.
