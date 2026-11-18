#!/bin/sh

set -e

REPO="rikkichy/zapret2-openwrt"
DEST="/tmp/zapret2-openwrt"
ARCHIVE="/tmp/zapret2-openwrt.tar.gz"
# Fetch the archive from its serving host without the github.com redirect.
URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/main"

fetch() {
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -T 10 -O "$2" "$1"
    elif command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 --max-time 60 -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -T 10 -O "$2" "$1"
    else
        echo "ERROR: no download tool found (need uclient-fetch, curl, or wget)"
        echo "Run: opkg update && opkg install uclient-fetch"
        exit 1
    fi
}

if [ "${1:-}" = --update ]; then
    work=$(mktemp -d /tmp/zapret2-update.XXXXXX)
    trap 'rm -rf "$work"' EXIT
    trap 'exit 1' HUP INT TERM
    fetch "$URL" "$work/repo.tar.gz"
    tar -xzf "$work/repo.tar.gz" -C "$work"
    service="$work/zapret2-openwrt-main/service.sh"
    if ! grep -qx 'UPDATE_PROTOCOL=1' "$service" || ! sh -n "$service"; then
        printf '%s\n' 'Invalid manager bundle or unsupported update protocol.' >&2
        exit 1
    fi
    sh "$service" --update
    exit
fi

echo ">> Downloading zapret2-openwrt..."
rm -rf "$DEST" "$ARCHIVE"
fetch "$URL" "$ARCHIVE"

echo ">> Extracting..."
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "$ARCHIVE" -C /tmp
rm -f "$ARCHIVE"
mv /tmp/zapret2-openwrt-main/* "$DEST"/
rm -rf /tmp/zapret2-openwrt-main

echo ">> Launching service manager..."
chmod +x "$DEST/service.sh"
exec "$DEST/service.sh"
