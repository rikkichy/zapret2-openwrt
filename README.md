# zapret2-openwrt

The default **flat** strategy is a measured DPI bypass for **zapret2** (`nfqws2`)
on OpenWrt and other Linux routers: Discord, YouTube, X/Twitter, Proton,
Cloudflare CDNs and Twitch emote services.

This is the zapret2 successor to
[zapret-openwrt](https://github.com/rikkichy/zapret-openwrt). That repo shipped
19 alternative strategies for zapret v1 and asked you to guess which one your
ISP needed. Here, **flat** remains the installation default. The second provider's
**sky** candidate is a separate [Docker-only experiment](#sky--docker-only-candidate).

> **zapret2 only.** `nfqws2` is a different engine from v1 `nfqws` — the
> `--dpi-desync=*` options no longer exist; strategies are Lua calls. This repo
> will not work against a zapret v1 install.

## sky — Docker-only candidate

**Docker only.** Nothing in the existing installer or service manager selects
`sky`; the `flat` installation and runtime behavior are unchanged.

The candidate, narrow YouTube/Discord/Proton/Anime365 hostlists, runner, and
acceptance probe live in [`strategies/sky/`](strategies/sky/). Its Dockerfile builds the measured
upstream revision inside the image and includes the existing Steam fake blob.
It does not require a sibling source checkout or a bare-metal zapret2 install.
The current image targets **Linux ARM64**, matching the measured rig.

### Running sky

Use a dedicated Linux Docker host with a packet-preserving network path.
On macOS, use Docker **inside the existing Lima `zapret` VM with vzNAT** and
the checkout mounted there, not Docker Desktop/default userspace networking.
Run these commands from this repository's root:

```sh
limactl start --tty=false zapret
limactl shell zapret sudo docker build \
  -f strategies/sky/Dockerfile -t zapret2-sky .
limactl shell zapret sudo docker run --rm --init --name zapret-sky \
  --privileged --network host zapret2-sky
```

On a Linux ARM64 Docker host, use the same `docker build` and `docker run`
commands without the `limactl shell zapret sudo` prefix.

The default command runs five fresh body-completion checks per URL/protocol,
then stops. A failed check returns nonzero. The container removes its own
`zapret_sky` nftables table and restores the changed conntrack sysctl on exit.
It refuses an existing table rather than deleting another experiment.
Do not run overlapping experiments in the same host network namespace.
`--privileged --network host` affects the Linux host's network, not just an
isolated Docker bridge; use the dedicated VM rather than an application server.

To obtain an off-control, run the probe without the strategy entrypoint:

```sh
limactl shell zapret sudo docker run --rm --network host \
  --entrypoint python3 zapret2-sky /sky/probe.py
```

Docker host networking means **the Linux VM**, not macOS. These commands do not
route the Mac's browser or Discord application through the candidate.
The runner rejects execution outside Docker. Do not install `sky` bare-metal.

### Evidence and limits

[`results.json`](strategies/sky/results.json) indexes the retained measurements,
including failures, source revision, and original runtime versions. The
59/60 body result belongs to the original test image, not an assertion that
every subsequent Docker rebuild or provider route has identical behavior.

- Unlike `flat`, `sky` uses **TCP timestamp fooling**, not a TTL-4 TLS fake.
  It requires a negotiated TCP Timestamp option; without one, the fake can
  corrupt the connection. See the exact profiles in
  [`strategy.args`](strategies/sky/strategy.args).
- YouTube and Discord have separate QUIC profiles. HTTP/3 checks prohibit
  fallback to TCP, so a successful HTTPS request is not misreported as QUIC.
- One TLS 1.2 thumbnail request failed in the five-repeat run. Do not erase
  that failure with retries or call this production-stable.
- Real YouTube media transfers and an unauthenticated Discord Gateway
  WebSocket Hello passed. Voice discovery/STUN were verified only with a
  loopback packet receiver; **live voice and screenshare remain unverified**.
- IPv4 only. `discordstatus.com` remains outside the core candidate with its
  body stall unresolved. Timestamp-less clients and real client routing need
  verification before promotion.

### Proton and Anime365 extension

[`services-results.json`](strategies/sky/services-results.json) records this
extension separately from the original YouTube/Discord results, with raw
failures and browser observations.

- **Anime365:** `anime-365.ru` and `smotret-anime.online` now use the existing TCP
  strategy and no-TTL QUIC fake. Both completed five normal-HTTPS and five
  HTTP/3-only login-page requests. An isolated browser routed through a
  temporary Docker HTTP proxy rendered the login page and loaded its scripts.
  The TCP peer rejects forced TLS 1.3; verified normal HTTPS negotiates TLS 1.2.
  Those forced-version failures are preserved, not presented as fixed.
- **Proton web:** the website, account sign-in, Drive, Calendar, Pass, and VPN
  website completed all 60 TLS 1.2/1.3 body checks. The account application
  rendered its sign-in form. No authenticated actions or VPN tunnel were tested.
- **Proton Mail is not fixed:** `mail.proton.me`, `mail.protonmail.com`, and
  `protonmail.com` failed all three direct TCP/443 attempts per address.
  `api.protonmail.ch` had one reachable and one unreachable address. Reachable
  API hosts returned structured unauthenticated HTTP 401 responses; this proves
  API transport, not mailbox access. TLS desync cannot repair a TCP connection
  that never establishes.

The probe checks the relevant transports per endpoint: normal HTTPS plus
advertised HTTP/3 for Anime365, TLS 1.2/1.3 for the tested Proton frontends.
It does not mislabel untested Proton HTTP/3 as blocking or claim the
unreachable mail frontends pass. The hostlists do not route ordinary Mac apps.


## Install
These instructions install **flat**, not the Docker-only `sky` candidate.


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
--lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:ip_ttl=4:repeats=6
--lua-desync=multidisorder:pos=1,host+1,midsld
```

Five profiles in one `nfqws2` instance — Hetzner-hosted hosts, general TLS,
HTTP, QUIC, and Discord voice/STUN. See
[`custom.d/50-zapret2-bypass`](custom.d/50-zapret2-bypass).

It was picked from 1896 discovery tests plus ~1400 repeat-verified tests
(`blockcheck2`, `SCANLEVEL=force`, `REPEATS=5`). Verification is on **body
completion**, not status codes — a `200` only proves headers arrived, and the
CDN block lets headers through before stalling the body. Against the full
target list it fixed 32 hostnames with **zero regressions**; `discord.com` now
delivers 170 KB, `discordstatus.com` 466 KB, `klipy.com` 2.4 MB. `yt-dlp`
pulls a 10-minute video, 15 MB at 7.5 MB/s — no mid-stream stall, no
throughput penalty.

Why each parameter:

| | |
|---|---|
| `ip_ttl=4` | the fake must expire between the DPI and the server. **The most path-specific value here** — re-tune it first if your ISP route differs. |
| `repeats=6` | not cosmetic. At `repeats=2`, discord.com and googlevideo fail. |
| `host+1` | required for `youtubei.googleapis.com` and `i.ytimg.com`; `midsld` alone is not enough. |
| QUIC blob | needs a **real** QUIC Initial (`quic_initial_www_google_com.bin`). The built-in `fake_default_quic` never worked. |
| voice fake | Discord voice/STUN needs a **real QUIC Initial** as the fake (1200 B) at `repeats=6` — not a block of zero bytes at `repeats=2`. The zero-byte version left foreign (non-RU) voice channels and screenshare unusable. |
| no `tcp_md5` | on the reference path the md5 fake reaches the *server* and corrupts the connection. `ip_ttl` and `badsum` fool it correctly. |
| `sni=www.google.com` | **the fake must carry a whitelisted SNI.** There are two separate blocks. Beating the ClientHello block alone leaves a second, response-side block on Cloudflare targets: handshake completes, headers arrive, body stalls forever. Over 6 GET trials × 6 hosts, a random-SNI fake completed **7/36** bodies; the same fake with `sni=www.google.com` completed **35/36**. |

Both fake blobs ship with zapret2 — there is nothing extra to copy.

## Discord voice

Voice and screenshare are UDP, on `19294-19344` and `50000-65535`, matched by
payload (`discord_ip_discovery`, `stun`) rather than by host. The fake for that
profile must be a **real QUIC Initial**, not zeros:

```
--lua-desync=fake:blob=voice_fake:repeats=6
```

`files/fake/quic_initial_steamcommunity_com.bin` (1200 B) is used by default —
the same payload the upstream Windows bundle ships as `ACTIVE_DISCORD_UDP.bin`,
which is what was confirmed working for foreign voice channels. Point
`NFQWS2_Z2B_VOICE_FAKE` at zapret2's own `quic_initial_www_google_com.bin` if
you would rather not add the file; it is the same size and shape.

Verified at packet level (nfqws2 classifies both payload types and emits 6 ×
1228-byte fakes). **Not verified end to end** — live voice needs the Discord
client, since the voice server only answers IP-discovery carrying an SSRC from
a real session.

TCP interception also covers Cloudflare's alternate HTTPS ports
(`2053,2083,2087,2096,8443`), which Discord uses for `discord.media`. Those
were measured as *not* blocked on the reference connection, so this is
coverage rather than a fix.

## Lists

| File | Purpose |
|---|---|
| `list-general.txt` | domains measured as blocked |
| `list-hetzner.txt` | 7tv — Hetzner (AS24940) gets a stricter ruleset and its own profile |
| `list-exclude.txt` | hosts the strategy would otherwise **break** (ships empty) |
| `zapret-hosts-user-ipban.txt` | IP-blocked hosts — need a proxy, see [IP blocks](#ip-blocks) |
| `files/fake/` | the Discord voice fake (see [Discord voice](#discord-voice)) |

`list-exclude.txt` ships **empty**. `discordstatus.com` used to be in it,
because the older random-SNI fake broke it — the current fake fixes it instead
(0/6 bodies without the bypass, 6/6 with). Add a host only if you measure it
working with zapret2 stopped and failing with it running.

Edit lists through menu option 7, or directly in `/opt/zapret2/ipset/`. Restart
to apply.

## Adding a site

Put the hostname in `lists/list-general.txt` and restart. Subdomains match
automatically. Before and after, verify on **body completion against a URL that
returns real content** — not the apex:

```sh
curl -sS -o /dev/null -w '%{http_code} %{size_download}B exit=%{exitcode}\n' \
     --max-time 18 'https://example.com/some/real/page'
```

A `200` only proves headers arrived, and a redirect proves less still: Anime365's
apex returns a 302 with an empty body, so it completes even while every real page
on the site hangs.

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

- **Some hosts are IP-blocked, not DPI-blocked** — the TCP handshake never
  completes, so there is no TLS exchange for a desync to act on and zapret2
  cannot help by design. Currently `mail.proton.me`, `api.protonmail.ch`,
  `protonmail.com`, `mail.protonmail.com` and `instagram.com`. Note the Proton
  block is *per-IP*: `proton.me`, `account.proton.me`, `calendar`, `drive` and
  `mail-api` all work — only Proton **Mail**'s front-ends are dropped, which is
  why the site and login work but the mailbox never opens. See
  [IP blocks](#ip-blocks).
- `googlevideo.com` and `youtube-nocookie.com` **apex** names stay blocked, but
  nothing uses them: video comes from `rrN---sn*.googlevideo.com` and embeds
  from `www.youtube-nocookie.com`, both of which work.
- **7tv.app / 7tv.io** get their own profile (Hetzner, AS24940, stricter
  ruleset). They were unblocked at the time of the last re-measurement, so that
  profile is insurance rather than something currently verified. `cdn.7tv.app`,
  which serves the actual emotes, was never blocked.
- Results are genuinely unstable run to run (ISP-side DPI load balancing). A
  single failed request does not mean the strategy is wrong.

## IP blocks

Run the detector with zapret2 **stopped** — the answer must not depend on the
bypass:

```sh
./tools/find-ipblocks.sh
```

It TCP-connects to every address of every host in `tools/probe-hosts.txt`,
three times, on ports 443 and 80, and reports the ones that never answer. It
also flags the case where only some of a host's addresses fail, which is
anycast noise rather than a block — Discord trips that regularly.

Anything it reports genuinely cannot be fixed here. `lists/zapret-hosts-user-ipban.txt`
holds the current set; copy it to `/opt/zapret2/ipset/` and the startup scripts
will resolve it into the kernel sets `ipban`/`ipban6`. zapret2 does not proxy
anything itself — those sets exist so you can match them in policy routing or a
selective proxy, sending only those hosts through a VPN while everything else
stays direct.

## Menu

```
STRATEGY   1. Install / reinstall strategy      2. Show installed
SERVICE    3. Start   4. Stop   5. Restart   6. Status
LISTS      7. Edit domain lists
TOOLS      8. Diagnostics   9. Uninstall
```

## License

GPL-3.0, same as the upstream project.
