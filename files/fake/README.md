# Extra fake payloads

`quic_initial_steamcommunity_com.bin` — a real 1200-byte QUIC Initial, used as
the fake for Discord voice/STUN UDP.

Taken from [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)
(MIT, © 2016-2026 bol-van, © 2024-2026 Flowseal), where it ships as
`ACTIVE_DISCORD_UDP.bin`. Reused here because that is the exact payload
confirmed working for foreign voice channels on the reference connection.

zapret2's own `files/fake/quic_initial_www_google_com.bin` is byte-identical to
Flowseal's Google blob and is a valid substitute if you prefer not to add files
— set `NFQWS2_Z2B_VOICE_FAKE` to point at it.
