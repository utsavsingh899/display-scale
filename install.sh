#!/bin/bash
# Install Display Scale, and the res and displaymode commands.
# Run it from the unzipped release folder: bash install.sh
#   - Display Scale.app goes to /Applications and opens. Its setup window takes you through the rest.
#   - res and displaymode go to ~/.local/bin (for Terminal users).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
APP="/Applications/Display Scale.app"

if [[ $(uname -m) != arm64 ]]; then
  echo "Display Scale works only on Mac computers with Apple silicon."
  exit 1
fi
if [[ ! -x "$HERE/displaymode" || ! -d "$HERE/Display Scale.app" ]]; then
  echo "Run this script from the unzipped release folder."
  echo "To build from source, run ./build.sh, then run build/display-scale/install.sh."
  exit 1
fi

# The command line tools.
mkdir -p "$BIN"
cp "$HERE/res" "$HERE/displaymode" "$BIN/"
chmod +x "$BIN/res" "$BIN/displaymode"
# A download or AirDrop adds a quarantine flag, and macOS then blocks the tools.
xattr -d com.apple.quarantine "$BIN/res" "$BIN/displaymode" 2>/dev/null || true
if ! grep -qs '\.local/bin' "$HOME/.zshrc"; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
  echo "Added ~/.local/bin to PATH in ~/.zshrc. Open a new terminal window before you use res."
fi
echo "Installed res and displaymode in $BIN"

# The app. An older copy goes to the Trash.
osascript -e 'quit app "Display Scale"' 2>/dev/null || true
if [[ -d $APP ]]; then
  mv "$APP" "$HOME/.Trash/Display Scale $(date '+%Y-%m-%d %-I.%M.%S %p').app"
fi
ditto "$HERE/Display Scale.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "Installed $APP"
echo
echo "Display Scale is open. Its icon (a small display) is in the menu bar."
echo "On the first start, its setup window takes you through the custom sizes."
