# zapret2-openwrt

The default **flat** strategy is a measured DPI bypass for **zapret2** (`nfqws2`)
on OpenWrt and other Linux routers: Discord, YouTube, X/Twitter, Proton,
Cloudflare CDNs and Twitch emote services.

This is the zapret2 successor to
[zapret-openwrt](https://github.com/rikkichy/zapret-openwrt). That repo shipped
19 alternative strategies for zapret v1 and asked you to guess which one your
ISP needed. Here, **flat** is the default for a new install, and the manager can
select **flat** or the second provider's [**sky** strategy](#sky--second-provider-strategy).

> **zapret2 only.** `nfqws2` is a different engine from v1 `nfqws` — the
> `--dpi-desync=*` options no longer exist; strategies are Lua calls. This repo
> will not work against a zapret v1 install.

## sky — second-provider strategy

Select **sky** in the native OpenWrt manager with option **1**, then **2**.
The first-run setup also asks which strategy to install. Local validation remains
Docker-only; native installation on your router is supported separately.

The candidate, narrow YouTube/Discord/Proton/Anime365 hostlists, runner, and
acceptance probe live in [`strategies/sky/`](strategies/sky/). Its Dockerfile builds the measured
upstream revision inside the image and includes the existing Steam fake blob.
It does not require a sibling source checkout or a bare-metal zapret2 install.
The Docker test image targets **Linux ARM64**, matching the measured rig.
Native OpenWrt uses the router's existing `nfqws2` binary, not that Docker image.

### Native selection and switching

The selected name is stored in the single installed `custom.d/50-zapret2-bypass`
entrypoint and survives reopening the manager and rebooting the router.
An existing legacy strategy is recognized as **flat**; updating the manager does
not silently switch it to sky. Enter keeps the current selection, and 0 cancels.

The manager prepares required files before stopping the old service, then installs
the new selection. Declining startup leaves the service stopped. Copy/start
failures restore prior runtime files when possible; unresolved recovery retains a
backup and prints its location.

Sky's native profiles and editable lists are installed under
`$ZAPRET_BASE/strategies/sky/`. Reinstalling preserves existing lists and the shared
`ipset/list-exclude.txt`; native profiles are regenerated from the canonical
[`strategy.args`](strategies/sky/strategy.args), using upstream queue allocation
and Lua initialization. Only one custom.d entrypoint is installed.

`shared.txt` restores flat's shared Cloudflare/ECH/CDN host group, including
`storage.googleapis.com`. It is used by sky's TLS and TTL-limited QUIC profiles.
YouTube/Anime365 keep their separate QUIC profile; no desync parameters changed.

**Existing sky installations:** update the manager, then select option **1 → 2**
to reinstall sky and start it. This installs the Discord DNS fix and updates native
profiles without overwriting your existing edited service lists.
Updating the manager alone does not change the running strategy.

Sky also installs a reversible **Discord DNS override** for exactly `discord.com`
and `updates.discord.com`. It uses the four reachable addresses in
[`discord-dns.sh`](strategies/sky/discord-dns.sh), matching Flowseal's hosts
workaround and avoiding the observed nonresponding address. These are measured
static addresses, not a guarantee against future routing changes.

The override uses OpenWrt dnsmasq's default `/tmp/hosts` directory and a SIGHUP,
not a DNS/DHCP restart. Native firewall start/stop hooks add/remove the managed
file, including on boot and restart; switching to flat or uninstalling removes
the integration. Existing user firewall hooks and unrelated DNS records remain.
This relies on normal `INIT_APPLY_FW=1` service operation.

**After reinstalling, fully quit and reopen Discord** to discard its cached bad
connection/address. Clients must use the router's DNS. With a different resolver
or `ignore_hosts_dir`, configure these two records in that resolver and set
`NFQWS2_Z2B_DISCORD_DNS=0` in zapret2's config. Sky otherwise refuses startup if
dnsmasq is not configured to read the hosts directory.
The [DNS fix verification](strategies/sky/evidence/discord-dns.json) records the
tested lifecycle and current updater results, including the remaining limits.

Existing port/packet overrides apply to both strategies. `NFQWS2_Z2B_OPT` and
`NFQWS2_Z2B_VOICE_FAKE` remain **flat-only**, so old flat options cannot silently
replace a sky selection. Sky is IPv4-only. Non-Discord TLS profiles still depend on negotiated TCP timestamps.
Native startup validates its arguments with `nfqws2 --dry-run`; Lua execution and
real client behavior still need runtime verification.

OpenWrt's embedded release stores Lua libraries as `*.lua.gz`. The manager
accepts either plain or gzip-compressed libraries, matching `nfqws2`'s own loader.
Leave packaged Lua files compressed; no manual rename or symlink is required.

The opt-in [`manager smoke test`](tools/test-strategy-manager.py) drives the real
menu through a PTY, using BusyBox tools and upstream native SysV/nftables helpers
inside Docker with compressed Lua assets matching the embedded release. It covers
switching, cancellation, user-list preservation, reopening the registered command,
invalid-profile rollback, uninstall, real dnsmasq start/stop resolution, and the live updater manifest/module download.
This is not a test of a physical router's procd boot.

After building the test image below, run it in the dedicated Lima VM:

```sh
limactl shell zapret sudo docker run --rm --init --name zapret-manager-test \
  --privileged --network host -v "$PWD:/repo:ro" --entrypoint bash zapret2-sky \
  -c 'apt-get update && apt-get install -y --no-install-recommends busybox dnsmasq-base && python3 /repo/tools/test-strategy-manager.py'
```

### Docker validation

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
The test runner rejects execution outside Docker. Use the manager, not this
runner or the Docker argument file directly, for native OpenWrt installation.

### Evidence and limits

[`results.json`](strategies/sky/results.json) indexes the retained measurements,
including failures, source revision, and original runtime versions. The
59/60 body result belongs to the original test image, not an assertion that
every subsequent Docker rebuild or provider route has identical behavior.

- Discord TLS has its own first-match, hostlisted profile using `tcp_ack=1000`
  on Google-SNI fakes. This replaces timestamp-only fooling for the client,
  updater, gateway, CDN, and `discord.media` HTTPS ports. Other service profiles
  remain unchanged; their `tcp_ts` fake still requires negotiated TCP timestamps.
  See [`strategy.args`](strategies/sky/strategy.args).
- YouTube and Discord have separate QUIC profiles. HTTP/3 checks prohibit
  fallback to TCP, so a successful HTTPS request is not misreported as QUIC.
- One TLS 1.2 thumbnail request failed in the five-repeat run. Do not erase
  that failure with retries or call this production-stable.
- Real YouTube media transfers and an unauthenticated Discord Gateway
  WebSocket Hello passed. Voice discovery/STUN were verified only with a
  loopback packet receiver; **live voice and screenshare remain unverified**.
- IPv4 only. `discordstatus.com` remains outside the core candidate with its
  body stall unresolved. The Discord timestamp-less regression checks completed
  HTTPS bodies, a CDN image, and a real unauthenticated Gateway WebSocket Hello.
  It does not establish authenticated client, live voice, or screenshare support.
  [Discord fix evidence](strategies/sky/evidence/discord-tcp-ack.json) also records
  the updater checksum, media TLS checks, UDP observations, and rejected candidates.

The manager smoke test above also runs the [Discord regression](tools/test-sky-discord.py)
with TCP timestamps disabled and restores them afterwards. It fetches the current
update manifest and verifies a module against its advertised SHA-256, then checks
HTTPS, CDN and Gateway WebSocket transport. The standalone Docker runner does not
install the native dnsmasq hooks; use the manager test to exercise the DNS fix.

The ACK modifier is zapret2's documented [TCP field operation](https://github.com/bol-van/zapret2/blob/master/docs/manual.en.md#standard-fooling),
not a copied v1 `--dpi-desync` option. [ALT4](https://github.com/Flowseal/zapret-discord-youtube/blob/main/general%20%28ALT4%29.bat)'s broad IP/game catch-all rules are not imported.
Reinstall **sky** with manager option **1 → 2** after updating these files;
updating the manager alone does not replace the running strategy.

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
unreachable mail frontends pass. The Docker rig does not route ordinary Mac apps;
native OpenWrt interception follows the router's existing LAN/WAN configuration.


## Install
The installer offers **flat** and **sky**; **flat** is the fresh-install default.


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
ask for **flat** or **sky**, copy the corresponding assets, and offer to start the
service. Afterwards, type `zapret2` to reopen the menu.

Manual install: copy this folder to the router and run `./service.sh`.

To update an older manager that has no selector, rerun the installer above.
Then use option **1** to choose a strategy. An existing installation remains
selected until you explicitly change it.

## The strategy
The following measurements and parameters describe **flat**.


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

Run `zapret2`; option **1** selects and installs **flat** or **sky**.
The current installed name appears beside that option. List editing and
diagnostics follow the selected strategy's deployed assets.

## License

GPL-3.0, same as the upstream project.
