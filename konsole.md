# Konsole Cheatsheet

## Tabs
| Shortcut | Action |
|---|---|
| Ctrl+Shift+T | New tab |
| Ctrl+Shift+W | Close tab |
| Shift+Left / Shift+Right | Switch tab |
| Ctrl+Shift+Left / Right | Move tab |
| Ctrl+Alt+S | Rename tab |

## Split Views
| Shortcut | Action |
|---|---|
| Ctrl+( | Split left/right |
| Ctrl+) | Split top/bottom |
| Ctrl+Shift+X | Close split pane |
| Ctrl+Shift+] | Grow split |
| Ctrl+Shift+[ | Shrink split |
| Ctrl+Tab | Next split pane |
| Ctrl+Shift+Tab | Previous split pane |

## Clipboard and Selection
| Shortcut | Action |
|---|---|
| Ctrl+Shift+C | Copy |
| Ctrl+Shift+V | Paste |
| Ctrl+Shift+X | Paste selection |
| Double-click | Select word |
| Triple-click | Select line |
| Shift+Scroll | Select by scrolling |

## Scrolling
| Shortcut | Action |
|---|---|
| Shift+PgUp / PgDn | Scroll page |
| Ctrl+Shift+K | Clear scrollback |
| Ctrl+Shift+Up / Down | Scroll one line |

## Font Size
| Shortcut | Action |
|---|---|
| Ctrl++ | Zoom in |
| Ctrl+- | Zoom out |
| Ctrl+0 | Reset zoom |

## Search and Navigation
| Shortcut | Action |
|---|---|
| Ctrl+Shift+F | Find in output |
| F3 / Shift+F3 | Next / previous match |
| Ctrl+click link | Open URL |

## Profiles and Settings
| Shortcut | Action |
|---|---|
| Ctrl+Shift+, | Edit current profile |
| Ctrl+Shift+M | Show/hide menu bar |
| Ctrl+Shift+S | New profile |
| Ctrl+Shift+B | Toggle bookmark bar |
| F11 | Fullscreen |

## Session Monitoring
| Shortcut | Action |
|---|---|
| Ctrl+Shift+I | Monitor silence (alert when idle) |
| Ctrl+Shift+A | Monitor activity (alert on new output) |

---

## Profile Setup

1. Copy `Awesome.profile` to `~/.local/share/konsole/`
2. Open Konsole then Settings then Manage Profiles then set Awesome as default
3. Install a Nerd Font: https://www.nerdfonts.com/font-downloads
4. Restart Konsole

## Recommended Shell Add-ons

- **Starship prompt**: `curl -sS https://starship.rs/install.sh | sh`
- **zsh-autosuggestions**: suggests commands as you type
- **zsh-syntax-highlighting**: colors valid/invalid commands
- **fzf**: fuzzy finder for history (Ctrl+R) and files (Ctrl+T)
- **eza**: modern ls with icons and git status
- **bat**: cat with syntax highlighting
- **zoxide**: smarter cd that learns your directories
