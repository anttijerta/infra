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

Clone to `/opt/infra` and run setup from the clone:

```sh
GIT_SSH_COMMAND="ssh -i /root/.ssh/infra_deploy_key -o IdentitiesOnly=yes" \
  git clone git@github.com:anttijerta/infra.git /opt/infra
bash /opt/infra/server/setup.sh
passwd <admin-user>
```

Hand the clone and the deploy key over to `<admin-user>`, so `git pull` works as that
user, and remove root's copy:

```sh
install -m 600 -o <admin-user> -g <admin-user> /root/.ssh/infra_deploy_key /home/<admin-user>/.ssh/infra_deploy_key
chown -R <admin-user>:<admin-user> /opt/infra
sudo -u <admin-user> git -C /opt/infra config core.sshCommand \
  "ssh -i ~/.ssh/infra_deploy_key -o IdentitiesOnly=yes"
sudo -u <admin-user> git -C /opt/infra pull
rm /root/.ssh/infra_deploy_key /root/.ssh/infra_deploy_key.pub
```

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

### 5. Create env files

```sh
sudo install -d -m 750 -o root -g docker /etc/demos
sudo install -m 640 -o root -g docker /opt/infra/env/caddy.env.example /etc/demos/caddy.env
sudo install -m 640 -o root -g docker /opt/infra/env/waste-sorter.env.example /etc/demos/waste-sorter.env
sudoedit /etc/demos/caddy.env /etc/demos/waste-sorter.env
cp /opt/infra/.env.example /opt/infra/.env
```

Fill in `ACME_EMAIL` and `APP_KEY` (`openssl rand -base64 32`). In `/opt/infra/.env`,
set `WASTE_SORTER_TAG` to a specific version to pin the image.

### 6. Start

```sh
cd /opt/infra
docker compose pull
docker compose up -d
```

### 7. Verify

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
