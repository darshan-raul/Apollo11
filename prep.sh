#!/usr/bin/env bash

# prep.sh - Apollo 11 environment setup (mise)
# Supports Linux (including WSL2) and macOS.
#
# Usage:
#   ./prep.sh            install mise, activate it in your shell, install tools
#   ./prep.sh --verify   only check that every tool is installed and on PATH
#
# Tools come from mise.toml next to this script. They are installed into your
# global mise config (~/.config/mise/config.toml) so they remain available
# after you check out the pinned course commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE_TOML="$SCRIPT_DIR/mise.toml"
MISE_BIN_DIR="$HOME/.local/bin"

# --- Helper Functions ---

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Tool names from the [tools] table of mise.toml (comments and other tables ignored).
read_tools() {
    awk '
        /^\[/ { in_tools = ($0 ~ /^\[tools\]/); next }
        in_tools && /^[[:space:]]*[A-Za-z0-9_:\/".-]+[[:space:]]*=/ {
            line = $0
            sub(/#.*/, "", line)
            split(line, kv, "=")
            name = kv[1]; ver = kv[2]
            gsub(/[[:space:]"]/, "", name); gsub(/[[:space:]"]/, "", ver)
            if (name != "") print name "@" ver
        }
    ' "$MISE_TOML"
}

# Binary to probe for each mise tool name, when it differs from the tool name.
tool_binary() {
    case "$1" in
        awscli) echo aws ;;
        *) echo "$1" ;;
    esac
}

check_docker() {
    if ! check_command docker; then
        echo "⚠️  Docker not found. mise does not install Docker (it needs a daemon)."
        echo "   Linux:  https://docs.docker.com/engine/install/"
        echo "   macOS / Windows (WSL2): https://docs.docker.com/desktop/"
        return 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo "⚠️  Docker Compose v2 not found (docker compose version failed)."
        return 1
    fi
    if ! docker ps >/dev/null 2>&1; then
        echo "⚠️  Docker is installed but the daemon is not reachable (docker ps failed)."
        echo "   Start Docker, or on Linux add yourself to the docker group."
        return 1
    fi
    echo "✅ docker: $(docker --version)"
}

verify() {
    local missing=0 spec name bin
    echo "🔍 Verifying Apollo 11 toolchain..."
    for c in git curl; do
        if check_command "$c"; then echo "✅ $c"; else echo "❌ $c not found"; missing=1; fi
    done
    check_docker || missing=1
    while read -r spec; do
        name="${spec%@*}"
        bin="$(tool_binary "$name")"
        if check_command "$bin"; then
            echo "✅ $bin -> $(command -v "$bin")"
        else
            echo "❌ $bin not found on PATH (mise tool: $name)"
            missing=1
        fi
    done < <(read_tools)
    if [ "$missing" -ne 0 ]; then
        echo ""
        echo "Some tools are missing. Run ./prep.sh, then restart your shell."
        return 1
    fi
    echo "🎉 All tools present."
}

detect_shell() {
    basename "${SHELL:-bash}"
}

get_profile_path() {
    case "$1" in
        bash)
            if [ "$(uname -s)" = "Darwin" ] && [ ! -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh) echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *) echo "$HOME/.profile" ;;
    esac
}

# Safely append to profile if not already present
append_to_profile() {
    local line="$1" file="$2"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -Fq "$line" "$file"; then
        echo "$line" >> "$file"
        echo "   Added: $line"
    else
        echo "   Skipped (already exists): $line"
    fi
}

# --- Entry point ---

if [ ! -f "$MISE_TOML" ]; then
    echo "❌ mise.toml not found next to prep.sh ($MISE_TOML)."
    exit 1
fi

case "${1:-}" in
    --verify) verify; exit $? ;;
    "") ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (use --verify or --help)"; exit 1 ;;
esac

echo "🚀 Initiating Apollo 11 Launch Preparation Sequence..."

for c in git curl; do
    check_command "$c" || { echo "❌ $c is required. Install it with your OS package manager first."; exit 1; }
done

# --- 1. Install mise ---

export PATH="$MISE_BIN_DIR:$PATH"
if ! check_command mise; then
    echo "📦 mise not found. Installing..."
    curl -fsSL https://mise.run | sh
    echo "✅ mise installed: $(mise --version)"
else
    echo "✅ mise is already installed: $(mise --version)"
fi

# --- 2. Configure Shell (activation & completion) ---

SHELL_NAME="$(detect_shell)"
PROFILE_PATH="$(get_profile_path "$SHELL_NAME")"
MISE_PATH="$(command -v mise)"

echo "🔧 Configuring shell profile: $PROFILE_PATH"

case "$SHELL_NAME" in
    bash|zsh)
        append_to_profile "eval \"\$($MISE_PATH activate $SHELL_NAME)\"" "$PROFILE_PATH"
        ;;
    fish)
        append_to_profile "$MISE_PATH activate fish | source" "$PROFILE_PATH"
        ;;
    *)
        # POSIX shells: no activate hook, put shims on PATH instead.
        append_to_profile "export PATH=\"\$HOME/.local/share/mise/shims:\$PATH\"" "$PROFILE_PATH"
        ;;
esac

echo "✅ Shell configuration updated."

# --- 3. Install project tools ---

echo "📦 Installing Apollo 11 tools globally via mise..."
TOOLS=()
while read -r spec; do TOOLS+=("$spec"); done < <(read_tools)  # bash 3.2 (macOS) has no mapfile
mise use --global --yes "${TOOLS[@]}"

# Also trust the repo config so `mise install` / auto-activation works inside the repo.
mise trust --yes "$MISE_TOML" >/dev/null 2>&1 || true

# Make the tools visible for the verify step in this process.
export PATH="$HOME/.local/share/mise/shims:$PATH"

echo "----------------------------------------------------------------"
verify || true
echo "----------------------------------------------------------------"
echo "🎉 Preparation Complete!"
echo "Restart your shell or run:"
echo "  source $PROFILE_PATH"
echo ""
echo "Re-check any time with:"
echo "  ./prep.sh --verify"
echo "----------------------------------------------------------------"
