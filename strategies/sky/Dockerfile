FROM debian:bookworm

RUN test "$(dpkg --print-architecture)" = arm64 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    make gcc zlib1g-dev libcap-dev libnetfilter-queue-dev libmnl-dev libsystemd-dev libluajit-5.1-dev \
    iptables nftables ipset iproute2 conntrack \
    curl ca-certificates dnsutils bind9-host ncat netcat-openbsd \
    procps psmisc gawk grep sed coreutils file xz-utils bsdextrautils \
    tcpdump net-tools less nano git openssl python3 traceroute iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# static curl with HTTP/3 (QUIC) + TLS1.3 + post-quantum, required by blockcheck2 for http3 tests
ADD https://github.com/stunnel/static-curl/releases/download/8.21.0/curl-linux-aarch64-glibc-8.21.0.tar.xz /tmp/curl.tar.xz
RUN tar -C /usr/local/bin -xJf /tmp/curl.tar.xz curl && rm /tmp/curl.tar.xz && \
    mv /usr/local/bin/curl /usr/local/bin/curl-http3 && chmod +x /usr/local/bin/curl-http3 && \
    /usr/local/bin/curl-http3 --version


# yt-dlp: real end-to-end YouTube playback verification (zipapp, uses python3 above)
ADD https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp /usr/local/bin/yt-dlp
RUN chmod 0755 /usr/local/bin/yt-dlp && /usr/local/bin/yt-dlp --version

WORKDIR /opt/zapret2
ADD https://codeload.github.com/bol-van/zapret2/tar.gz/a0be7cbb40a4230e4b60fc33b7ea06102eb8ec15 /tmp/zapret2.tar.gz
RUN tar -xzf /tmp/zapret2.tar.gz --strip-components=1 -C /opt/zapret2 && rm /tmp/zapret2.tar.gz
RUN make -C /opt/zapret2 || make -C /opt/zapret2 systemd
COPY files/fake/quic_initial_steamcommunity_com.bin /opt/zapret2/files/fake/
COPY strategies/sky/strategy.args strategies/sky/run.sh strategies/sky/probe.py strategies/sky/youtube.txt strategies/sky/discord.txt strategies/sky/proton.txt strategies/sky/anime.txt strategies/sky/shared.txt /sky/
WORKDIR /sky
ENTRYPOINT ["bash", "/sky/run.sh"]
CMD ["python3", "/sky/probe.py"]
