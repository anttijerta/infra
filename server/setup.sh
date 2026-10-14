#!/usr/bin/env bash
# One-time server setup for the demo host. Run as root on a fresh Ubuntu LTS
# server. Safe to run again: every step checks or overwrites its own state.
set -euo pipefail

# Usage: ADMIN_USER=<name> bash setup.sh

if [[ $EUID -ne 0 ]]; then
	echo "Run as root." >&2
	exit 1
fi

ADMIN_USER=${ADMIN_USER:-}
if [[ -z $ADMIN_USER ]]; then
	echo "ADMIN_USER is required. Usage: ADMIN_USER=<name> bash setup.sh" >&2
	exit 1
fi
if [[ ! $ADMIN_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ || $ADMIN_USER == root ]]; then
	echo "ADMIN_USER '${ADMIN_USER}' is not a valid non-root user name." >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Base packages"
apt-get update
apt-get install -y ufw unattended-upgrades ca-certificates curl

echo "==> Admin user ${ADMIN_USER}"
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
	useradd -m -s /bin/bash "$ADMIN_USER"
fi
# No password is set here and sudo is not NOPASSWD: set one with `passwd`.
usermod -aG sudo "$ADMIN_USER"

admin_home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$admin_home/.ssh"
install -m 600 -o "$ADMIN_USER" -g "$ADMIN_USER" \
	/root/.ssh/authorized_keys "$admin_home/.ssh/authorized_keys"

# Lockout guard: never disable root login unless the admin user has a key.
if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$admin_home/.ssh/authorized_keys"; then
	echo "No SSH keys for ${ADMIN_USER}; not hardening SSH." >&2
	exit 1
fi

echo "==> SSH hardening"
# sshd uses the first value it reads, so 00- wins over cloud-init's 50- file.
cat >/etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sshd -t
systemctl reload ssh

echo "==> Firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
# HTTP/3 (QUIC) for Caddy.
ufw allow 443/udp
ufw --force enable

echo "==> Unattended security upgrades"
# Ubuntu's default 50unattended-upgrades only allows the security pocket.
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

echo "==> Docker Engine"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
	if dpkg -s "$pkg" >/dev/null 2>&1; then
		apt-get remove -y "$pkg"
	fi
done
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck source=/dev/null
codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Trade-off: docker group membership is root-equivalent. Accepted so the admin
# can run compose without sudo; the account is key-only over SSH.
usermod -aG docker "$ADMIN_USER"

cat <<EOF

Done. Next:
  1. passwd ${ADMIN_USER}
  2. In a NEW terminal, confirm: ssh ${ADMIN_USER}@<server>  and  sudo -v
  3. Only then close this root session.
EOF
