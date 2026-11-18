# Working on zapret2-openwrt

- **Install, upgrade, or recover:** read [Operations](docs/INSTALL.md) before touching a router. Preserve the user's proxy and router state unless the task authorizes a change.
- **Connectivity regression, strategy port, or Docker setup:** read [Validation](docs/VALIDATION.md) before measuring. Prove direct egress and record an off-control before comparing profiles. Diagnose the failing transport stage, not just the hostname.
- **Sky, Flowseal 1.10.4, or Discord voice:** read the [Sky incident record](docs/SKY-INCIDENT.md) before changing profiles. Reuse the measured controls, not the old addresses or conclusions without retesting. Voice TLS, UDP discovery, and a signed-in join are separate checks.
