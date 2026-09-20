# Sourced from zapret2's config only while sky is selected.
# Preserve existing firewall hooks; OpenWrt/procd does not call daemon stop hooks.
Z2B_DNS_PREVIOUS_UP="${INIT_FW_POST_UP_HOOK:-}"
Z2B_DNS_PREVIOUS_DOWN="${INIT_FW_POST_DOWN_HOOK:-}"

z2b_discord_dns()
(
	set -e
	file=/tmp/hosts/zapret2-sky-discord
	if [ "$1" = 0 ] || [ "${NFQWS2_Z2B_DISCORD_DNS:-1}" = 0 ]; then
		[ -e "$file" ] || exit 0
		rm -f "$file"
	else
		# OpenWrt's default dnsmasq reads /tmp/hosts on SIGHUP. Refuse a
		# custom resolver layout rather than claiming an unused file fixes DNS.
		found=0
		for config in /var/etc/dnsmasq.conf.* /etc/dnsmasq.conf; do
			[ -r "$config" ] || continue
			if grep -Eq '^(addn-hosts|hostsdir)=/tmp/hosts/?$' "$config"; then
				found=1
				break
			fi
		done
		if [ "$found" = 0 ]; then
			echo 'zapret2-sky: dnsmasq must read /tmp/hosts; for another resolver, configure the two Discord records there and set NFQWS2_Z2B_DISCORD_DNS=0 in config' >&2
			exit 1
		fi
		mkdir -p /tmp/hosts
		tmp=$(mktemp /tmp/zapret2-sky-discord.XXXXXX)
		trap 'rm -f "$tmp"' EXIT
		# ponytail: measured static addresses, matching Flowseal's hosts fix;
		# revisit this set if routing changes. No wildcard/subdomain override.
		cat > "$tmp" <<'HOSTS'
162.159.138.232 discord.com updates.discord.com
162.159.137.232 discord.com updates.discord.com
162.159.128.233 discord.com updates.discord.com
162.159.135.232 discord.com updates.discord.com
HOSTS
		chmod 644 "$tmp"
		mv -f "$tmp" "$file"
	fi
	# No restart: preserve DHCP leases/listeners and reload only hosts/cache.
	pids=$(pidof dnsmasq) || pids=
	[ -z "$pids" ] || kill -HUP $pids
)

z2b_discord_dns_up()
{
	if [ -n "$Z2B_DNS_PREVIOUS_UP" ]; then
		$Z2B_DNS_PREVIOUS_UP || exit 1
	fi
	z2b_discord_dns 1 || exit 1
}

z2b_discord_dns_down()
{
	# Remove our override even if a user's unrelated down hook fails.
	z2b_discord_dns 0 || exit 1
	if [ -n "$Z2B_DNS_PREVIOUS_DOWN" ]; then
		$Z2B_DNS_PREVIOUS_DOWN || exit 1
	fi
}

INIT_FW_POST_UP_HOOK=z2b_discord_dns_up
INIT_FW_POST_DOWN_HOOK=z2b_discord_dns_down
