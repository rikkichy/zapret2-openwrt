#!/bin/sh
# Find hosts that are IP-blocked rather than DPI-blocked.
#
# A DPI block still completes the TCP handshake, then interferes with TLS -
# zapret2 can fix those. An IP block drops packets outright, so the handshake
# never completes and NO desync strategy can help. Those need a proxy/VPN,
# routed selectively via zapret2's ipban list + policy routing.
#
# Usage:  ./find-ipblocks.sh [hostfile]      (default: probe-hosts.txt)
#
# Run with zapret2 STOPPED - the answer must not depend on the bypass.

DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTFILE="${1:-$DIR/probe-hosts.txt}"
TRIES=3

connect_ok() {
    if command -v nc >/dev/null 2>&1; then nc -z -w 3 "$1" "$2" >/dev/null 2>&1
    else timeout 4 sh -c "echo >/dev/tcp/$1/$2" >/dev/null 2>&1; fi
}
ip_reachable() {
    # retry before declaring a block - anycast and packet loss cause false positives
    i=0
    while [ $i -lt $TRIES ]; do
        connect_ok "$1" 443 && return 0
        connect_ok "$1" 80  && return 0
        i=$((i + 1))
    done
    return 1
}

echo "# IP-blocked addresses - TCP handshake fails on both 80 and 443, ${TRIES}x"
echo "# generated $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "#"
total=0
while IFS= read -r host; do
    case "$host" in ''|\#*) continue ;; esac
    ips=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u)
    [ -z "$ips" ] && { echo "# $host -> NXDOMAIN"; continue; }
    n=0; bad=0; badlist=""
    for ip in $ips; do
        n=$((n + 1))
        if ! ip_reachable "$ip"; then bad=$((bad + 1)); badlist="$badlist $ip"; fi
    done
    if [ "$bad" -gt 0 ]; then
        for ip in $badlist; do echo "$ip    # $host"; done
        if [ "$bad" -lt "$n" ]; then
            echo "#   ^ NOTE: only $bad of $n addresses for $host - likely anycast, not a block"
        fi
        total=$((total + bad))
    fi
done < "$HOSTFILE"
echo "#"
[ "$total" = 0 ] && echo "# none - every probed address completes a TCP handshake" \
                 || echo "# $total address(es) unreachable. Feed the real ones to ipban + policy routing."
