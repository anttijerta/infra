# infra

Server setup for Jerta's public demos: one UpCloud server (Ubuntu LTS, Helsinki)
running Docker Compose behind Caddy. Secrets live only in env files on the
server, never in this repo.

## Layout

| Path | Purpose |
| --- | --- |
| `server/setup.sh` | One-time, idempotent host setup (run as root) |
| `docker-compose.yml` | Caddy and the demo apps |
| `Caddyfile` | Hostnames, automatic HTTPS, security headers |
| `.env.example` | Compose variables (env file directory, image tags) |
| `env/*.env.example` | Templates for the per-service env files on the server |

## Setup

### 1. Create the server

In UpCloud, create a server with the latest Ubuntu LTS in the Helsinki zone and
add your SSH public key. Note its public IPv4 (and IPv6) address.

### 2. DNS record

Create an `A` record (and `AAAA` if IPv6 is enabled) for `waste-sorter.jerta.fi`
pointing to the server. Wait until it resolves:

```sh
dig +short waste-sorter.jerta.fi
```

Caddy cannot obtain a certificate before DNS points to the server.

### 3. Clone the repo and run setup.sh

As root on the server, create a deploy key for this repo:

```sh
ssh-keygen -t ed25519 -N "" -C "infra deploy key" -f /root/.ssh/infra_deploy_key
cat /root/.ssh/infra_deploy_key.pub
```

In GitHub, add the public key under the repo's Settings → Deploy keys, with
"Allow write access" left unchecked (read-only).

Outbound port 22 to GitHub is blocked from the UpCloud server, so reach GitHub's
SSH service on port 443 instead. Create `/root/.ssh/config`:

```sh
cat >/root/.ssh/config <<'EOF'
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/infra_deploy_key
  IdentitiesOnly yes
EOF
chmod 600 /root/.ssh/config
```

The first connection asks you to accept the host key for `[ssh.github.com]:443`;
compare it with GitHub's published SSH key fingerprints before accepting.

Clone to `/opt/infra` and run setup from the clone:

```sh
git clone git@github.com:anttijerta/infra.git /opt/infra
ADMIN_USER=<admin-user> bash /opt/infra/server/setup.sh
passwd <admin-user>
```

Hand the clone, the deploy key and the SSH config over to `<admin-user>`, so `git pull`
works as that user, and remove root's copies:

```sh
install -m 600 -o <admin-user> -g <admin-user> /root/.ssh/infra_deploy_key /home/<admin-user>/.ssh/infra_deploy_key
install -m 600 -o <admin-user> -g <admin-user> /root/.ssh/config /home/<admin-user>/.ssh/config
chown -R <admin-user>:<admin-user> /opt/infra
sudo -u <admin-user> git -C /opt/infra pull
rm /root/.ssh/infra_deploy_key /root/.ssh/infra_deploy_key.pub /root/.ssh/config
```

`<admin-user>` gets the same host key prompt on the first pull.

Keep the root session open. In a new terminal, confirm `ssh <admin-user>@<server>` and
`sudo -v` work before closing it; root login is disabled from now on.

### 4. Log in to GHCR

Create a GitHub personal access token (classic) with only the `read:packages`
scope, then as `<admin-user>`:

```sh
docker login ghcr.io -u <github-user>
```

Paste the token when prompted. Docker stores it in `~/.docker/config.json`
(base64, not encrypted); it is read-only, so a leak exposes images only.

The token has an expiry date. Note it, and before it expires create a new token
and run `docker login ghcr.io` again. An expired token shows up as
`unauthorized` or `denied` errors from `docker compose pull`.

### 5. Create env files

`docker compose` reads env files as the user running it, so `/etc/demos` and the
files in it belong to `<admin-user>` and are readable by nobody else:

```sh
sudo install -d -m 700 -o <admin-user> -g <admin-user> /etc/demos
install -m 600 /opt/infra/env/caddy.env.example /etc/demos/caddy.env
install -m 600 /opt/infra/env/waste-sorter.env.example /etc/demos/waste-sorter.env
cp /opt/infra/.env.example /opt/infra/.env
```

Edit `/etc/demos/caddy.env` and `/etc/demos/waste-sorter.env` as `<admin-user>`, and fill
in `ACME_EMAIL` and `APP_KEY` (`openssl rand -base64 32`). In `/opt/infra/.env`,
set `WASTE_SORTER_TAG` to a specific version to pin the image.

### 6. Upgrade and reboot

Install pending updates before starting services, and reboot if the kernel or
core libraries changed:

```sh
sudo apt update && sudo apt upgrade -y
[ -f /var/run/reboot-required ] && sudo reboot
```

After a reboot, log in again as `<admin-user>`.

### 7. Start

```sh
cd /opt/infra
docker compose pull
docker compose up -d
```

### 8. Verify

```sh
docker compose ps                                 # both services up, waste-sorter healthy
curl -I https://waste-sorter.jerta.fi             # 200 with security headers
curl https://waste-sorter.jerta.fi/health         # {"status":"ok"}
docker compose logs caddy | grep -i certificate   # certificate obtained
sudo ufw status                                   # only 22, 80, 443
```

## Updating

```sh
cd /opt/infra
git pull
# Optionally change WASTE_SORTER_TAG in .env
docker compose pull
docker compose up -d
```
