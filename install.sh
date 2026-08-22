#!/bin/sh

set -e

REPO="rikkichy/zapret2-openwrt"
DEST="/tmp/zapret2-openwrt"
ARCHIVE="/tmp/zapret2-openwrt.tar.gz"
URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"

fetch() {
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$2" "$1"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "ERROR: no download tool found (need uclient-fetch, curl, or wget)"
        echo "Run: opkg update && opkg install uclient-fetch"
        exit 1
    fi
}

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
