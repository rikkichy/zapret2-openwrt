# Sky incident record: Discord and YouTube

These observations apply to the second provider and the measured routes. Read [Validation](VALIDATION.md) before repeating the work. The [arguments](../strategies/sky/strategy.args), [DNS hook](../strategies/sky/discord-dns.sh), and [asset provenance](../files/fake/README.md) own the shipped configuration.

## November 2026: service recovery

**Path first.** Lima `vzNAT` initially returned FlClash fake IPs and downloaded both homepages with Sky off. Pinning real addresses still did not prove direct egress. Those results were discarded. A signed Tart guest bridged to physical Wi-Fi acquired a LAN lease. Docker used the router directly and showed ISP hops and real service addresses. FlClash remained running. The router strategy was off for the initial comparison.

**Initial comparison.** Without Sky, none of 36 page, thumbnail, and Gateway API checks completed. Stock Sky fixed all 18 YouTube checks and the nine Gateway API checks. The Discord homepage still stalled over TCP after headers. None of the five Flowseal 1.10.4 blob swaps fixed that reliably. Keep working YouTube and QUIC profiles.

| Failure | Decisive comparison | Resulting decision |
| --- | --- | --- |
| Discord homepage stalls after HTTP 200 | Pin each IPv4 address with the same hostname. The four previously pinned addresses failed all 60 TCP body checks. The previously omitted address completed all 15. | Update `discord.com` only. Keep the updater pool: each address still returned complete manifests. |
| Main Gateway WebSocket cannot negotiate TLS | Curl reached HTTP. Python TLS timed out on all five addresses. The narrow Flowseal ALT11 port restored TLS and the unauthenticated Hello with timestamps disabled. | Give the Gateway a first-match profile. Use ACK-based packet handling. |
| YouTube page opens, but the video will not load | `yt-dlp` got media URLs but failed TCP TLS. HTTP/3 got a complete 64 KiB range. Removing the fake restored TCP transfers. | Use plain multidisorder for `googlevideo.com` TCP only. |

The packaged change passed 60 core checks: four resources, three transports, and five fresh requests each. It downloaded two MP4s of 322,379 and 15,298,808 bytes. Discord checks completed the updater module and verified its checksum, the homepage, a CDN avatar, and the Gateway Hello. Four sampled UDP discovery endpoints answered with Sky active. Three answered in the off-control. This was not a live call.

The native DNS hook separately passed start/stop, scoped record, and unrelated-record checks with real dnsmasq. The broader manager smoke test installed the strategy but stopped on an `i.scdn.co` thumbnail timeout. That failure was not resolved by this change. The test did not use physical OpenWrt procd. See [the service recovery commit](https://github.com/rikkichy/zapret2-openwrt/commit/c9bf1a8673fbe067823345904ea7e195dca425d2). The full session logs remain in the local lab, not in this repository.

## November 2026: voice signaling follow-up

The user reported that Discord started but could not join voice. The router already served the updated DNS records. Its exact failing voice assignment was unavailable. Two previously observed Finland voice hostnames were tested on TCP 443 and 2087, with the router strategy active. All ten connections reached TCP and then timed out in TLS. Applying the existing Gateway TLS profile to voice signaling made all ten complete.

The shipped profile passed ten voice TLS handshakes and five main Gateway TLS handshakes. TCP timestamps were disabled in the bridged Docker lab. Voice UDP was unchanged. This fixes the reproduced signaling failure. Authenticated joins, audio, and screenshare were not measured. See [the voice signaling commit](https://github.com/rikkichy/zapret2-openwrt/commit/626e72e48e).

## Earlier measurements

- [Initial Sky measurements](../strategies/sky/results.json) record the earlier 59/60 result, including the failed TLS 1.2 thumbnail request. They do not describe the November configuration. The reported playback and voice loopback evidence are separate checks.
- [Sky service extension](../strategies/sky/services-results.json) records scoped Proton web and Anime365 results. Normal HTTPS worked for Anime365 even though forced TLS 1.3 failed. Reachable Proton API responses did not establish mailbox access. Do not generalize an HTTP status or one address to a whole service.
- [Original Discord DNS verification](../strategies/sky/evidence/discord-dns.json) documents the hook lifecycle and an older address pool. The November measurements supersede its address selection, not its historical result.
- [Installer isolation](../strategies/sky/evidence/installer-isolation.json) records the two-engine conflict. Keep the managed overlay and rollback path intact when testing profile changes.

## Flat comparison

Flat belongs to the original provider. The [flat entrypoint](../custom.d/50-zapret2-bypass) records its profile rationale. Historical tests found that recovering the TLS handshake did not always recover a larger CDN body. The fixed TTL and the fake SNI mattered on that route. Neither result is a default for Sky. The dedicated Hetzner profile was not validated against a live block during the last flat recheck.
