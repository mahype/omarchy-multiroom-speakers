#!/bin/bash
# Builds a current OwnTone for multiroom mode and installs it for this user.
#
# OwnTone 29.3 (the AUR package) sends an AirPlay user agent that HomePod OS 27
# rejects with "403 Forbidden". The fix is merged upstream but not released
# yet, so this script builds a pinned upstream commit into
#   ~/.local/share/omarchy-multiroom-speakers/owntone
# where the plugin looks first. Nothing is installed system-wide and no sudo
# is needed once the build dependencies are there:
#
#   yay -S owntone-server        # pulls in all runtime and build dependencies
#
# Usage: tools/build-owntone.sh [commit]

set -euo pipefail

COMMIT="${1:-4fa5dccfb69622f42e77bd05628034a69a567d57}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-multiroom-speakers"
PREFIX="$DATA/owntone"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-multiroom-speakers/owntone-src"

for tool in git autoreconf make gcc pkg-config gperf; do
  command -v "$tool" >/dev/null || { echo "missing: $tool (install base-devel and gperf)" >&2; exit 1; }
done

if [[ ! -d $SRC/.git ]]; then
  mkdir -p "$(dirname "$SRC")"
  git clone --filter=blob:none https://github.com/owntone/owntone-server.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet --detach "$COMMIT"

cd "$SRC"
autoreconf -fi >/dev/null
./configure --quiet --prefix="$PREFIX" --sysconfdir="$PREFIX/etc" --localstatedir="$PREFIX/var" \
  --disable-install-user --disable-install-systemd --without-alsa --with-pulseaudio --enable-chromecast
# Paths are compiled in; a build for another prefix must not be reused.
make clean >/dev/null 2>&1 || true
make -j"$(nproc)" >/dev/null
make install >/dev/null

"$PREFIX/sbin/owntone" --version 2>/dev/null | head -1 || true
grep -qaF "AirPlay/999.0.0" "$PREFIX/sbin/owntone" && echo "HomePod OS 27: supported"
echo "Installed to $PREFIX/sbin/owntone"
echo "Optional, for PTP timing (better sync with HomePods):"
echo "  sudo setcap cap_net_bind_service=+ep $PREFIX/sbin/owntone"
