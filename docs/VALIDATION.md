# Validate a strategy on its actual route

For service regressions, Flowseal imports, and Docker setup, use this runbook.
[Operations](INSTALL.md) covers the router. The [Sky incident record](SKY-INCIDENT.md) shows what these checks found.

## 1. Prove the network path

Use a dedicated ARM64 Linux Docker host on the affected Internet connection.
On macOS, run it in a Linux VM.
Docker `--network host` shares the Linux namespace, not the macOS network.

- **Without a host TUN:** the existing Lima `vzNAT` setup can be sufficient for TCP and QUIC. Test packet fidelity for any mechanism you compare. Prior paired captures showed that this NAT can rewrite UDP source ports and reassemble fragments. Traceroute alone cannot attest to packet fidelity.
- **With a host TUN such as FlClash:** leave it running. Use a bridged Linux VM with its own LAN lease. A Docker bridge, `--noproxy '*'`, or `curl --resolve` alone cannot bypass a macOS TUN. Use a physical bridge instead of Docker Desktop or a userspace gateway.
- **On macOS without sudo:** the [signed Tart release](https://github.com/openai/tart/releases) provides `--net-bridged` through Apple's networking entitlement. Verify the release signature. `tart run VM --net-bridged=list` reports the physical interfaces and exits. Enter the active interface in `tart run VM --net-bridged=en0 --no-graphics`. Use a guest provisioned with the [Tart guest agent](https://github.com/openai/tart-guest-agent) for `tart exec` without SSH.

  The measured setup reused a powered-off Lima VM's cloned disk and Docker image. It retained the MAC expected by the guest's DHCP configuration. Keep the two VMs from using the same MAC at the same time. Stage the checkout on the guest disk if Docker cannot bind from the host share.

Confirm the route from **inside Docker**. Check `ip -4 route get 1.1.1.1`, `getent ahostsv4` on the service names, and `traceroute -4 -n 8.8.8.8`. Expect the LAN router followed by ISP hops on a bridged VM. Treat `198.18.0.0/15` DNS answers as evidence of fake-IP proxying. Confirm that an unrelated HTTPS control downloads a real body. For candidates that depend on packet shape, inspect the packets at egress.

**Ready:** the test container uses the intended gateway, DNS answers are real, and the positive control works. Keep router zapret2 off for direct comparisons, with permission, or explicitly label the test as router-on. A local container with no strategy is not an off-control if the router still handles its traffic.

## 2. Record the failing stage

Start with the user's observation. Test the closest controlled equivalent, not a generic homepage check. Record the host, port, DNS result, selected address, IP family, protocol, exit status, HTTP status, and completed bytes. Measure these stages separately:

| What fails | Next check |
| --- | --- |
| DNS | Compare client and router answers. Look for a DNS override, DoH, or fake IP. |
| TCP connect | Check each address and the exact port. A timeout is not proof of an IP block. Do not infer the TCP stage from curl timing fields alone. |
| TLS | Confirm TCP connection first. Try the affected client's TLS stack or ClientHello shape, not only curl. Keep SNI and ports unchanged. |
| Response body | Use GET on a real resource. Require a successful exit and the expected body. HTTP 200 and empty redirects are not evidence of completion. |
| HTTP/3 | Use `--http3-only` with an HTTP/3-capable curl. Require the negotiated version to be 3. |
| Intermittent CDN failure | Pin each DNS address with `curl --resolve`. Preserve the hostname, SNI, and port. Repeat per address. |
| Voice join | Separate the main Gateway, voice WebSocket, UDP discovery, and signed-in session. See [voice triage](#voice-triage). |

Use a bounded GET for a body probe. Substitute the failing hostname, one DNS answer, and a path with known content:

```sh
curl -4 --noproxy '*' --resolve "$host:443:$ip" --max-time 15 \
  -sS -o /dev/null -w 'http=%{http_code} bytes=%{size_download} exit=%{exitcode}\n' \
  "https://$host/$path"
```

For YouTube, test a watch page, a thumbnail, and completed transfers from actual video URLs. Use `yt-dlp` or a browser to get fresh URLs. Download short and sustained samples. Confirm output size and file type. A signed media URL may contain client identifiers or authorization data. Do not save it in public logs.

**Ready:** a narrow probe distinguishes the observed failure from a working control. If you cannot reproduce it, record the missing client or route evidence before changing production options.

## 3. Compare on the same Docker host

Run from the repository root on the dedicated Linux host. Use the same path, timeout, client, and acceptance check for both runs.

```sh
docker build -f strategies/sky/Dockerfile -t zapret2-sky .
docker run --rm --network host --entrypoint python3 zapret2-sky /sky/probe.py
docker run --rm --init --privileged --network host zapret2-sky
```

The first `docker run` is the off-control. The second uses the packaged profile. Both use [the same body probe](../strategies/sky/probe.py). When using a VM, run these commands from the guest checkout. Use `limactl shell zapret` on Lima or `tart exec VM` on Tart. Give Docker the needed guest privileges.

Run one strategy at a time. The [runner](../strategies/sky/run.sh) owns its table and restores its conntrack setting on exit. Privileged host-network containers must stay on the dedicated lab host.

- Start with off, stock, and one changed variable. Screen candidates against the narrow failure first. Confirm the winner on fresh connections and retain failed trials. Five repeats per endpoint and transport are the standard body check here.
- Flowseal's Windows strategies use zapret v1. Read the release and inspect the payloads separately from the flags. Match their roles to zapret2's [documented Lua operations](https://github.com/bol-van/zapret2/blob/master/docs/manual.en.md). Compare checksums against shipped assets. Treat matching bytes as reuse, not a new strategy. Keep the unaffected hostlists and transports unchanged. First matching profile wins.
- To check a standalone argument file, add `--dry-run` **inside** it. The engine reads argument files when `@file` is the first argument. A dry run does not exercise Lua or packet handling. Run the candidate in Docker before scoring it.
- Use timestamp-disabled checks for clients that may not negotiate TCP timestamps. Restore the guest sysctl afterward. A passing drop control proves interception only. An unrelated HTTPS control can reveal a fake that breaks working traffic.

**Ready:** the candidate fixes the original failure and preserves the relevant controls. Keep exact payloads, profiles, protocol, and measurement scope in the evidence. Do not promote a candidate that only worked once or only started successfully.

## 4. Verify packaging and client behavior

Rebuild the final image from the repository. Repeat the failing interaction with the final assets and profiles. Run the [Discord regression](../tools/test-sky-discord.py) with the intended DNS answers. It verifies the update manifest, module checksum, HTML, CDN image, and an unauthenticated Gateway Hello. It restores TCP timestamps.

The Docker runner does not apply the router's DNS hook. Use `--add-host` for the measured names in the container, or use the native manager test below. Keep that override out of the off-control unless you are comparing transport only.

The [manager smoke test](../tools/test-strategy-manager.py) uses BusyBox, `dnsmasq-base`, real nftables, and upstream SysV helpers. It exercises installed arguments, DNS lifecycle, and rollback. It does not verify physical OpenWrt procd or a logged-in client. Run it separately from the strategy runner:

```sh
docker run --rm --init --privileged --network host \
  -v "$PWD:/repo:ro" --entrypoint bash zapret2-sky \
  -c 'apt-get update && apt-get install -y --no-install-recommends busybox dnsmasq-base && python3 /repo/tools/test-strategy-manager.py'
```

Keep any unrelated smoke failure visible. Check the narrow changed behavior separately if the full test stops first. Check that no experiment containers or owned nftables hooks remain and that sysctls are restored. Leave unrelated tables, the host proxy, and the router untouched.

### Voice triage

1. Use a fresh client observation or a sanitized RTC log. Share only stage, timestamp, server hostname and port, and any assigned UDP destination. Do not retain raw logs, session identifiers, SSRCs, or tokens.
2. If the client has a voice hostname, test TCP and TLS against that exact hostname and port. Check the relevant address records and use the affected TLS stack. A TLS timeout comes before UDP discovery. Validate main Gateway behavior separately when changing a shared profile.
3. If the voice WebSocket reached `READY` and UDP discovery times out, inspect the **assigned UDP address and port**. Compare with an independent path or a controlled router capture. A fresh diagnostic identifier and a valid echo prove discovery only. Silence from an old or unassigned server does not prove an IP block.
4. For full acceptance, test a signed-in join, bidirectional audio, and screenshare where requested. If the current client or endpoint is unavailable, report the exact highest verified stage. Do not infer a live join from a main Gateway Hello or a UDP echo.
