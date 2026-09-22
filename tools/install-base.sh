#!/bin/sh
# Install a fresh OpenWrt base without install_easy.sh or starting zapret2.
# Dependency/architecture/service handling stays with the pinned upstream scripts.
umask 0022
source_dir=$1
target=/opt/zapret2
[ "$(id -u)" = 0 ] && [ -f /etc/openwrt_release ] || {
    echo 'Base bootstrap requires OpenWrt and root.' >&2; exit 1;
}
[ ! -e "$target" ] && [ ! -L "$target" ] || {
    echo "Refusing to overwrite existing $target; use the existing base." >&2; exit 1;
}
for file in config.default install_prereq.sh install_bin.sh common/installer.sh init.d/openwrt/zapret2; do
    [ -f "$source_dir/$file" ] || { echo "Missing upstream asset: $file" >&2; exit 1; }
done
# A fresh bootstrap must not replace somebody else's service integration.
for file in /etc/init.d/zapret2 /etc/hotplug.d/iface/90-zapret2 /etc/firewall.zapret2; do
    if [ -e "$file" ] || [ -L "$file" ]; then
        echo "Existing service integration must be reviewed first: $file" >&2
        exit 1
    fi
done
mkdir -p /opt || exit 1
stage=$(mktemp -d /opt/.zapret2-install.XXXXXX) || exit 1
installed=0
fw_registered=0
cleanup()
{
    rc=$?
    trap - EXIT
    if [ "$rc" != 0 ] && [ "$installed" = 1 ]; then
        [ "$fw_registered" != 1 ] || remove_openwrt_firewall
        if [ "$(readlink /etc/init.d/zapret2)" = "$target/init.d/openwrt/zapret2" ]; then
            /etc/init.d/zapret2 disable
            rm -f /etc/init.d/zapret2
        fi
        [ "$(readlink /etc/hotplug.d/iface/90-zapret2)" != "$target/init.d/openwrt/90-zapret2" ] ||
            rm -f /etc/hotplug.d/iface/90-zapret2
        rm -rf "$target"
    fi
    rm -rf "$stage"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -R "$source_dir"/. "$stage"/ && chmod 755 "$stage" &&
    cp -p "$stage/config.default" "$stage/config" || exit 1
# Keep the base inert, including if the router reboots before strategy selection.
printf '\nNFQWS2_ENABLE=0\n' >> "$stage/config" || exit 1
ZAPRET_BASE="$stage" ZAPRET_RW="$stage" ZAPRET_CONFIG="$stage/config" 
export ZAPRET_BASE ZAPRET_RW ZAPRET_CONFIG
sh "$stage/install_prereq.sh" || exit 1
sh "$stage/install_bin.sh" || exit 1
mkdir -p "$stage/tmp" "$stage/init.d/openwrt/custom.d" || exit 1
cp -p "$stage/ipset/zapret-hosts-user-exclude.txt.default" "$stage/ipset/zapret-hosts-user-exclude.txt" || exit 1
printf '%s\n' nonexistent.domain > "$stage/ipset/zapret-hosts-user.txt" || exit 1
: > "$stage/ipset/zapret-hosts-user-ipban.txt" || exit 1
mv "$stage" "$target" || exit 1
installed=1
EXEDIR="$target"
ZAPRET_BASE="$target"
ZAPRET_RW="$target"
ZAPRET_CONFIG="$target/config"
. "$ZAPRET_CONFIG"
. "$target/common/base.sh"
. "$target/common/fwtype.sh"
. "$target/common/dialog.sh"
. "$target/common/ipt.sh"
. "$target/common/installer.sh"
fix_sbin_path
fsleep_setup
check_system
[ "$SYSTEM" = openwrt ] || exit 1
INIT_SCRIPT_SRC="$target/init.d/openwrt/zapret2"
OPENWRT_IFACE_HOOK="$target/init.d/openwrt/90-zapret2"
FW_SCRIPT_SRC="$target/init.d/openwrt/firewall.zapret2"
OPENWRT_FW_INCLUDE=/etc/firewall.zapret2
# Do not reuse or remove a pre-existing UCI include with no corresponding file.
if openwrt_fw_section_find >/dev/null; then
    echo 'Existing zapret2 firewall include must be reviewed first.' >&2
    exit 1
fi
install_sysv_init || exit 1
install_openwrt_iface_hook || exit 1
if [ -n "$OPENWRT_FW3" ] && [ "$FWTYPE" = iptables ]; then
    fw_registered=1
    install_openwrt_firewall || exit 1
fi
# No service_start_sysv, firewall restart, list download or cron installation.
# The manager installs the selected custom strategy before offering to start it.
echo "zapret2 base installed at $target; service is stopped."
