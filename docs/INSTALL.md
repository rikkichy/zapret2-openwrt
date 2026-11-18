# Install and operate zapret2-openwrt

This manager runs **zapret2** (`nfqws2`) on OpenWrt and compatible Linux routers. It is the successor to [zapret-openwrt](https://github.com/rikkichy/zapret-openwrt). The zapret v1 executable and `--dpi-desync` options are not compatible.

| Strategy | Use |
| --- | --- |
| **flat** | Fresh-install default for the original provider. Covers Discord, YouTube, X, Proton web, and selected CDN and emote hosts. See the [flat profiles](../custom.d/50-zapret2-bypass). |
| **sky** | Second-provider, IPv4-only strategy. Covers Discord, YouTube, Proton web, Anime365, and selected shared CDN hosts. See the [Sky profiles and lists](../strategies/sky/) and [incident record](SKY-INCIDENT.md). |

Neither strategy is a proxy or VPN. Select the one measured on your route. Use the [validation runbook](VALIDATION.md) if neither fits.

## Install or update

Disable system-wide firewall flow offloading before you install a strategy. The manager refuses an incompatible configuration. It does not change selective zapret offload settings.

On the router, over SSH, run:

```sh
uclient-fetch -O- https://raw.githubusercontent.com/rikkichy/zapret2-openwrt/main/install.sh | sh
```

If `uclient-fetch` is unavailable, use `wget -O-` in its place. Review [the installer](../install.sh) first. For a manual install, copy the complete checkout to the router and run `sh service.sh` in that directory.

1. On a fresh install, accept the zapret2 base setup if needed. Select **flat** or **sky** when prompted.
2. Answer the startup prompt. Declining leaves the service stopped.
3. Reopen the registered manager by running `zapret2`.

### Update with `u`

If your menu has no **u**, run the installer above once to update the manager. It reuses the installed base. Then open `zapret2`, select **u**, and confirm.

The update downloads the latest bundle from GitHub `main` and refreshes the selected strategy. It does not switch strategies or reinstall the zapret2 base. It preserves edited lists and user overrides. A running service restarts. A stopped service stays stopped. If applying the update fails, the manager attempts to restore the previous bundle and strategy.

Use **1** to choose or reinstall a strategy from the local bundle. Enter retains the current selection. **0** cancels. The manager recognizes a legacy install as flat and keeps it selected until you switch.

The [base bootstrap](../tools/install-base.sh) reuses an existing zapret2 base. For a fresh base, it stages the embedded release and registers upstream startup links without starting the service. It does not restart the firewall, download lists, create cron jobs, or invoke `install_easy.sh`.

Rollback can leave packages that the package manager installed. See the [bootstrap test](../tools/test-base-install.sh) for checks that cover startup and reuse.

## Selection, configuration, and recovery

The manager prepares the new assets before stopping the old service. It installs one custom entrypoint and disables the upstream built-in strategy through a managed configuration block. This prevents two engines from handling the same traffic. It preserves the original setting for uninstall or rollback.

Sky's [canonical arguments](../strategies/sky/strategy.args) also serve Docker. [The manager](../service.sh) converts paths and adds the shared host exclusion. Zapret2 assigns the queue and loads Lua. Use the manager instead of copying Docker arguments directly onto the router. Keep packaged Lua archives compressed. Native startup checks paths and options with `nfqws2 --dry-run`. This does not exercise Lua or traffic.

Use menu **7** to edit the installed lists for the active strategy. Restart after editing. Reinstallation preserves user lists, the shared exclusion list, and existing fake files. It replaces the managed profiles. Subdomains match by default. Add a host to the exclusion list only after a comparison shows that the strategy breaks an otherwise working request.

The [custom entrypoint](../custom.d/50-zapret2-bypass) owns firewall port and packet-count defaults. Existing `NFQWS2_Z2B_*` port and packet overrides apply to both strategies. An old override can omit a port that the current strategy expects. `NFQWS2_Z2B_OPT` and `NFQWS2_Z2B_VOICE_FAKE` apply only to flat.

If a switch fails, the manager attempts to restore the previous runtime files and service state. If it reports a recovery directory, retain that backup and follow the printed recovery instructions. Do not run both strategies at once. Use menu **9** to remove the managed strategy and restore the original upstream configuration. User lists and the zapret2 base remain.

## Sky: Discord DNS and client startup

The [DNS hook](../strategies/sky/discord-dns.sh) manages only `discord.com` and `updates.discord.com`. It writes a file under `/tmp/hosts` and reloads dnsmasq without restarting DHCP. Start applies the records. Stop, a switch to flat, or uninstall removes them. Existing user hooks remain in place. This requires `INIT_APPLY_FW=1` and a dnsmasq configuration that reads `/tmp/hosts`.

Use the router DNS on the client. After reinstalling, completely quit and reopen Discord so it makes new connections. If you use another resolver, configure the two records there. Set `NFQWS2_Z2B_DISCORD_DNS=0` in the zapret2 config. Otherwise, Sky refuses startup when the native DNS hook cannot operate.

The source hook owns the addresses. These measurements apply to one route. They are not permanent Discord assignments.

## Hosts that do not establish TCP

Run [the TCP reachability check](../tools/find-ipblocks.sh) on a direct route with zapret2 stopped. It checks IPv4 addresses for the supplied hosts. A failed TCP connection is a reachability symptom, not proof of the cause. Confirm the address and port before calling it an IP block. TLS profiles cannot act on connections that never reach TLS.

[`zapret-hosts-user-ipban.txt`](../lists/zapret-hosts-user-ipban.txt) is input for zapret2's IP sets. The sets do not redirect traffic by themselves. Configure policy routing or a selective proxy separately if needed. A working Proton sign-in page does not establish mailbox access. See the [service evidence](../strategies/sky/services-results.json).

License: [GPL-3.0](../LICENSE).
