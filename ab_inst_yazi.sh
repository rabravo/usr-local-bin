#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Simple Yazi installer (Conda base only)
# -------------------------------

# 1) Ensure conda exists
if ! command -v conda &>/dev/null; then
  echo "ERROR: conda is not on PATH. Initialize or load conda first."
  exit 1
fi

# 2) Ensure we're in the *base* environment (no activation done here)
CURRENT_ENV="${CONDA_DEFAULT_ENV:-unknown}"
if [[ "$CURRENT_ENV" != "base" ]]; then
  echo "ERROR: You are in '$CURRENT_ENV', not 'base'."
  echo "Please switch to base first (e.g., 'conda deactivate' until you see (base)) and re-run."
  exit 1
fi

echo "✅ Detected Conda environment: base"

# 3) Choose installer
if command -v mamba &>/dev/null; then
  INSTALLER="mamba"
else
  INSTALLER="conda"
fi
echo "Using $INSTALLER for package installation."

# 4) Install Yazi + useful preview helpers
# (kept lightweight; no compilers, no ueberzugpp build)
$INSTALLER install -c conda-forge -y \
  yazi \
  fd ripgrep fzf jq zoxide p7zip \
  imagemagick chafa libsixel poppler

# 5) Minimal Yazi config
mkdir -p "${HOME}/.config/yazi"
CONFIG_FILE="${HOME}/.config/yazi/yazi.toml"

# If the file doesn't exist, create it with sane preview notes
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<'EOF'
# ~/.config/yazi/yazi.toml
[preview]
# Image preview depends on your terminal's graphics support.
# Options you can try (uncomment exactly one):
# image = "kitty"     # Kitty / WezTerm with kitty protocol
# image = "sixel"     # Terminals with SIXEL support (libsixel installed)
# image = "chafa"     # ASCII/Unicode graphics preview (works anywhere)
#
# If none of the above render, stick with chafa:
# image = "chafa"

# Default to chafa for broad compatibility; change later if your terminal supports images.
image = "chafa"
EOF
else
  # Ensure at least the [preview] section exists with a safe default
  if ! grep -q '^\[preview\]' "$CONFIG_FILE"; then
    {
      echo
      echo "[preview]"
      echo 'image = "chafa"'
    } >> "$CONFIG_FILE"
  fi
fi

echo
echo "🎉 Yazi installed to Conda base."
echo "Try it: yazi --debug"
echo
echo "Tips:"
echo "  - If you're on Kitty/WezTerm, set 'image = \"kitty\"' in ~/.config/yazi/yazi.toml"
echo "  - If your terminal supports SIXEL, set 'image = \"sixel\"'"
echo "  - 'chafa' works everywhere (text-mode previews)"
