#!/bin/bash

# prep.sh - Apollo 11 Environment Setup (Devbox)
# Supports Linux (including WSL), macOS

set -e

echo "🚀 Initiating Apollo 11 Launch Preparation Sequence..."

# --- Helper Functions ---

check_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_shell() {
    SHELL_NAME=$(basename "$SHELL")
    echo "$SHELL_NAME"
}

get_profile_path() {
    local shell_name="$1"
    case "$shell_name" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then echo "$HOME/.bashrc"; else echo "$HOME/.bash_profile"; fi
            ;;
        zsh)
            echo "$HOME/.zshrc"
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# --- 1. Install Devbox ---

if ! check_command devbox; then
    echo "📦 Devbox not found. Installing..."
    curl -fsSL https://get.jetpack.io/devbox | bash
    echo "✅ Devbox installed."
else
    echo "✅ Devbox is already installed."
fi

# --- 2. Configure Shell (Autocomplete & Eval) ---

SHELL_NAME=$(detect_shell)
PROFILE_PATH=$(get_profile_path "$SHELL_NAME")

echo "🔧 Configuring shell profile: $PROFILE_PATH"

# Function to safely append to profile if not already present
append_to_profile() {
    local line="$1"
    local file="$2"
    if ! grep -Fq "$line" "$file"; then
        echo "$line" >> "$file"
        echo "   Added: $line"
    else
        echo "   Skipped (already exists): $line"
    fi
}

# Add devbox global shellenv to profile (optional but good for global tools)
# For project specific usage, usually `devbox shell` is used.
# However, user asked to "put autocomplete and devbox eval in bash/zsh profile".
# Assuming they want the devbox environment to be easily accessible or global.
# We will match the user request:

# Devbox Eval (Hook)
# Typically users use `eval "$(devbox global shellenv)"` for global packages.
# Or they use `devbox shell` to enter the env.
# The user specifically asked for "devbox eval", likely meaning `eval "$(devbox global shellenv)"` 
# OR they might mean the `direnv` hook if they want auto-loading.
# Given "anywhere in linux", global shellenv makes the most sense if they treat this as a tools installer.

append_to_profile 'eval "$(devbox global shellenv)"' "$PROFILE_PATH"

# Autocomplete
if [ "$SHELL_NAME" = "bash" ] || [ "$SHELL_NAME" = "zsh" ]; then
    append_to_profile "source <(devbox completion $SHELL_NAME)" "$PROFILE_PATH"
fi

echo "✅ Shell configuration updated."

# --- 3. Install Project Packages ---

echo "📦 Installing project dependencies via Devbox..."

# Ensure devbox.json exists (it should be in the repo, but checking just in case)
if [ ! -f "devbox.json" ]; then
    echo "⚠️ devbox.json not found in current directory!"
    echo "   Creating default devbox.json..."
    devbox init
    devbox add kubectl minikube k3d docker go-task
fi

# Install packages
devbox install

echo "----------------------------------------------------------------"
echo "🎉 Preparation Complete!"
echo "----------------------------------------------------------------"
echo "Environment setup finished."
echo "Please restart your shell or run:"
echo "  source $PROFILE_PATH"
echo ""
echo "To enter the development shell, run:"
echo "  devbox shell"
echo "----------------------------------------------------------------"
