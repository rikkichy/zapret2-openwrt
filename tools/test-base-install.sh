#!/bin/sh
# Run in a disposable OpenWrt Docker container with the extracted upstream release
# as $1. stdin supplies the upstream prerequisite prompts (nftables for this test).
set -eu
[ -f /.dockerenv ] && [ -f /etc/openwrt_release ] || {
    echo 'OpenWrt Docker ONLY' >&2; exit 1;
}
[ ! -e /opt/zapret2 ] || { echo 'Use a fresh container' >&2; exit 1; }
before=$(nft -s list ruleset)
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$script_dir/install-base.sh" "$1"
if pidof nfqws2 >/dev/null; then
    echo 'Bootstrap unexpectedly started nfqws2' >&2; exit 1
fi
[ "$(nft -s list ruleset)" = "$before" ] || {
    echo 'Bootstrap unexpectedly changed firewall rules' >&2; exit 1;
}
ZAPRET_BASE=/opt/zapret2
. "$ZAPRET_BASE/config"
[ "$NFQWS2_ENABLE" = 0 ]
[ -x "$ZAPRET_BASE/nfq2/nfqws2" ]
/etc/init.d/zapret2 enabled
[ "$(readlink /etc/hotplug.d/iface/90-zapret2)" = "$ZAPRET_BASE/init.d/openwrt/90-zapret2" ]
config_hash=$(sha256sum "$ZAPRET_BASE/config")
if sh "$script_dir/install-base.sh" "$1"; then
    echo 'Bootstrap unexpectedly accepted an existing base' >&2; exit 1
fi
[ "$(sha256sum "$ZAPRET_BASE/config")" = "$config_hash" ]
printf '%s\n' 'PASS: real dependencies/binaries/service links installed; no daemon or firewall startup; existing base preserved'
