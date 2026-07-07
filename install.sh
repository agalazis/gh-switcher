#!/usr/bin/env bash

set -e

# Target directory and file
TARGET_DIR="$HOME/.gh-switcher"
TARGET_FILE="$TARGET_DIR/gh_switcher.sh"

# Repository URL for agalazis
GITHUB_REPO_URL="https://raw.githubusercontent.com/agalazis/gh-switcher/main/gh_switcher.sh"

echo "=== Installing gh-switcher ==="

# 1. Create target directory
mkdir -p "$TARGET_DIR"

# 2. Download the script
echo "Downloading gh_switcher.sh..."
if curl -sSfL "$GITHUB_REPO_URL" -o "$TARGET_FILE"; then
    echo "Successfully downloaded script to $TARGET_FILE"
else
    echo "Error: Failed to download gh_switcher.sh from $GITHUB_REPO_URL" >&2
    exit 1
fi

# 3. Detect shell and select config file
SHELL_NAME=$(basename "$SHELL")
SHELL_CONFIG=""

case "$SHELL_NAME" in
    bash)
        if [[ -f "$HOME/.bashrc" ]]; then
            SHELL_CONFIG="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            SHELL_CONFIG="$HOME/.bash_profile"
        fi
        ;;
    zsh)
        if [[ -f "$HOME/.zshrc" ]]; then
            SHELL_CONFIG="$HOME/.zshrc"
        fi
        ;;
esac

if [[ -z "$SHELL_CONFIG" ]]; then
    # Fallback to .bashrc
    SHELL_CONFIG="$HOME/.bashrc"
fi

# 4. Add source line to shell config
SOURCE_LINE="source $TARGET_FILE"

if grep -Fxq "$SOURCE_LINE" "$SHELL_CONFIG" 2>/dev/null; then
    echo "Shell configuration already includes sourcing of gh-switcher in $SHELL_CONFIG"
else
    echo "Adding gh-switcher source command to $SHELL_CONFIG..."
    echo -e "\n# GitHub Account Switcher Wrapper\n$SOURCE_LINE" >> "$SHELL_CONFIG"
    echo "Added successfully."
fi

echo "=== Installation Complete ==="
echo "Please reload your shell or run:"
echo "    source $TARGET_FILE"
