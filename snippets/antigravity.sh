#!/usr/bin/env zsh
# snippet: antigravity.sh - Antigravity agentic platform tools

# Check if agy (Antigravity CLI) is installed
if command -v agy &>/dev/null; then
    alias ag="agy"
    alias ag.="agy ."
fi

# Quota and usage tracking
if command -v antigravity-usage &>/dev/null; then
    alias quota="antigravity-usage"
fi
