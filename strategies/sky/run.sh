#!/bin/bash
# sky: Docker-only candidate. Build/run commands are in the repository README.
# The command runs with the candidate active; EXIT removes only our table and
# restores the VM sysctl. Do not run concurrent experiments in this namespace.
set -euo pipefail
[[ -f /.dockerenv && $(uname -s) == Linux ]] || { echo 'Docker ONLY' >&2; exit 1; }
[[ $# -gt 0 ]] || { echo 'Usage: bash /sky/run.sh COMMAND [ARGS...]' >&2; exit 2; }
Z=/opt/zapret2
TABLE=zapret_sky
# Refuse rather than deleting another experiment's table/queue.
if nft list table inet "$TABLE" >/dev/null 2>&1; then
    echo "$TABLE already exists; stop its owner first" >&2; exit 1
fi
old=$(sysctl -n net.netfilter.nf_conntrack_tcp_be_liberal)
pid=
created=0
cleanup() {
    rc=$?
    trap - EXIT
    if [[ -n $pid ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    if [[ $created == 1 ]]; then nft delete table inet "$TABLE" || rc=1; fi
    sysctl -w "net.netfilter.nf_conntrack_tcp_be_liberal=$old" >/dev/null || rc=1
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$Z/nfq2/nfqws2" @/sky/strategy.args >/tmp/sky-nfqws2.log 2>&1 &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then cat /tmp/sky-nfqws2.log >&2; exit 1; fi
sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1 >/dev/null
nft -f - <<'NFT'
table inet zapret_sky {
    chain post {
        type filter hook postrouting priority 101; policy accept;
        meta nfproto ipv4 meta mark and 0x40000000 == 0 ct direction original tcp dport { 443, 2053, 2083, 2087, 2096, 8443 } ct original packets 1-20 counter queue num 252 bypass
        meta nfproto ipv4 meta mark and 0x40000000 == 0 ct direction original udp dport { 443, 19294-19344, 50000-65535 } ct original packets 1-8 counter queue num 252 bypass
    }
    chain pre {
        type filter hook prerouting priority -101; policy accept;
        meta nfproto ipv4 meta mark and 0x40000000 == 0 ct direction reply tcp sport { 443, 2053, 2083, 2087, 2096, 8443 } ct reply packets 1-10 counter queue num 252 bypass
        meta nfproto ipv4 meta mark and 0x40000000 == 0 ct direction reply udp sport { 443, 19294-19344, 50000-65535 } ct reply packets 1-4 counter queue num 252 bypass
    }
    chain raw {
        type filter hook output priority -401; policy accept;
        meta nfproto ipv4 meta mark and 0x40000000 != 0 notrack
    }
}
NFT
created=1
"$@"
kill -0 "$pid"
