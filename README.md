# zapret2-openwrt

One measured DPI-bypass strategy for **zapret2** (`nfqws2`) on OpenWrt and other
Linux routers. Discord, YouTube, X/Twitter, Proton, Cloudflare CDNs and the
Twitch emote services.

This is the zapret2 successor to
[zapret-openwrt](https://github.com/rikkichy/zapret-openwrt). That repo shipped
19 alternative strategies for zapret v1 and asked you to guess which one your
ISP needed. This one ships **a single strategy that was measured**, and nothing
else.

> **zapret2 only.** `nfqws2` is a different engine from v1 `nfqws` — the
> `--dpi-desync=*` options no longer exist; strategies are Lua calls. This repo
> will not work against a zapret v1 install.

## Install

On the router, over SSH:

```sh
uclient-fetch -O- https://raw.githubusercontent.com/rikkichy/zapret2-openwrt/main/install.sh | sh
```

or, if `uclient-fetch` is missing:

```sh
wget -O- https://raw.githubusercontent.com/rikkichy/zapret2-openwrt/main/install.sh | sh
```

That fetches the repo and opens the interactive manager, which will offer to
install the zapret2 base (`v1.0.4`, openwrt-embedded) if it isn't there yet,
copy the lists, install the strategy and start the service. Afterwards, type
`zapret2` to reopen the menu.

Manual install: copy this folder to the router and run `./service.sh`.

## The strategy

```
--payload=tls_client_hello
--lua-desync=fake:blob=fake_default_tls:ip_ttl=4:repeats=6
--lua-desync=multidisorder:pos=1,host+1,midsld
```

Five profiles in one `nfqws2` instance — Hetzner-hosted hosts, general TLS,
HTTP, QUIC, and Discord voice/STUN. See
[`custom.d/50-zapret2-bypass`](custom.d/50-zapret2-bypass).

It was picked from 1896 discovery tests plus ~1400 repeat-verified tests
(`blockcheck2`, `SCANLEVEL=force`, `REPEATS=5`), and cleared 44 of 51 blocked
hostnames on TLS 1.2, TLS 1.3 and QUIC alike. Verified end to end with
`yt-dlp`: a 10-minute video pulled 15 MB at 7.5 MB/s, so there is no mid-stream
("16 KB") stall and no throughput penalty.

Why each parameter:

| | |
|---|---|
| `ip_ttl=4` | the fake must expire between the DPI and the server. **The most path-specific value here** — re-tune it first if your ISP route differs. |
| `repeats=6` | not cosmetic. At `repeats=2`, discord.com and googlevideo fail. |
| `host+1` | required for `youtubei.googleapis.com` and `i.ytimg.com`; `midsld` alone is not enough. |
| QUIC blob | needs a **real** QUIC Initial (`quic_initial_www_google_com.bin`). The built-in `fake_default_quic` never worked. |
| no `tcp_md5` | on the reference path the md5 fake reaches the *server* and corrupts the connection. `ip_ttl` and `badsum` fool it correctly. |

Both fake blobs ship with zapret2 — there is nothing extra to copy.

## Lists

| File | Purpose |
|---|---|
| `list-general.txt` | domains measured as blocked |
| `list-hetzner.txt` | 7tv — Hetzner (AS24940) gets a stricter ruleset and its own profile |
| `list-exclude.txt` | hosts the strategy would otherwise **break** |

`list-exclude.txt` matters. `discordstatus.com` is not blocked, and applying the
strategy to it turns a working 200 into a timeout. Anything you find behaving
that way belongs in this file.

Edit lists through menu option 7, or directly in `/opt/zapret2/ipset/`. Restart
to apply.

## Re-tuning for your ISP

DPI behaviour is path- and time-specific. If a site stays blocked, `ip_ttl` is
the first knob:

```sh
# on a machine with the zapret2 source, sweep TTL against one domain
BATCH=1 DOMAINS=youtube.com SKIP_DNSCHECK=1 SKIP_IPBLOCK=1 \
  SCANLEVEL=force REPEATS=5 /opt/zapret2/blockcheck2.sh
```

Override anything from the zapret2 config file without editing the script:

```sh
NFQWS2_Z2B_OPT="--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=..."
NFQWS2_Z2B_PORTS_TCP="80,443"
NFQWS2_Z2B_PORTS_UDP="443,50000-65535"
```

## Known limits

- **instagram.com is an IP block** — TCP 443 never connects. No desync strategy
  can fix that; it needs a proxy or VPN.
- `googlevideo.com` and `youtube-nocookie.com` **apex** names stay blocked, but
  nothing uses them: video comes from `rrN---sn*.googlevideo.com` and embeds
  from `www.youtube-nocookie.com`, both of which work.
- **7tv.app / 7tv.io** are only intermittently reachable. `cdn.7tv.app`, which
  serves the actual emotes, was never blocked — emotes load in chat even when
  the 7tv site does not.
- Results are genuinely unstable run to run (ISP-side DPI load balancing). A
  single failed request does not mean the strategy is wrong.

## Menu

```
STRATEGY   1. Install / reinstall strategy      2. Show installed
SERVICE    3. Start   4. Stop   5. Restart   6. Status
LISTS      7. Edit domain lists
TOOLS      8. Diagnostics   9. Uninstall
```

## License

GPL-3.0, same as the upstream project.
