# debug

## cannot get back to `zsh`

```bash
# What shell is currently set as default?
echo $SHELL

# Is zsh actually installed?
command -v zsh

# What does /etc/passwd say your shell is?
grep "^$(whoami):" /etc/passwd

# Is zsh listed as a valid login shell?
grep zsh /etc/shells

zsh_path="$(command -v zsh)"
echo "Detected zsh at: $zsh_path"
# Ensure this path is present in /etc/shells before running chsh/usermod.
chsh -s "$zsh_path"

# If that doesn't stick, here are the usual culprits:
# chsh silently fails — openSUSE sometimes uses usermod instead.
sudo usermod -s "$zsh_path" "$(whoami)"

grep -n 'bash\|SHELL' ~/.bashrc ~/.bash_profile ~/.profile ~/.login 2>/dev/null

# zsh config is broken
# if zsh launches but immediately drops you back to bash,
# your ~/.zshrc might have an error. Test with:
zsh --no-rcs

```
