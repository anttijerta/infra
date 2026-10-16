# infra

Server setup for Jerta's public demos: one UpCloud server (Ubuntu LTS, Helsinki)
running Docker Compose behind Caddy. Secrets live only in env files on the
server, never in this repo.

Demo app: [waste-sorter](https://github.com/anttijerta/waste-sorter).

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

As root on the server, clone to `/opt/infra` over HTTPS and run setup from the
clone:

```sh
git clone https://github.com/anttijerta/infra.git /opt/infra
ADMIN_USER=<admin-user> bash /opt/infra/server/setup.sh
passwd <admin-user>
```

Hand the clone over to `<admin-user>`, so `git pull` works as that user:

```sh
chown -R <admin-user>:<admin-user> /opt/infra
sudo -u <admin-user> git -C /opt/infra pull
```

Keep the root session open. In a new terminal, confirm `ssh <admin-user>@<server>` and
`sudo -v` work before closing it; root login is disabled from now on.

> **Forking into a private repo?** An HTTPS clone then needs credentials. Use a
> read-only deploy key instead:
>
> 1. As root, run `ssh-keygen -t ed25519 -N "" -f /root/.ssh/infra_deploy_key`
>    and add the `.pub` file under the repo's Settings → Deploy keys, with
>    "Allow write access" left unchecked.
> 2. If outbound port 22 to GitHub is blocked (it was on our UpCloud server),
>    create `/root/.ssh/config` (mode 600) to use GitHub's SSH service on
>    port 443:
>
>    ```
>    Host github.com
>      HostName ssh.github.com
>      Port 443
>      User git
>      IdentityFile ~/.ssh/infra_deploy_key
>      IdentitiesOnly yes
>    ```
>
>    Compare the `[ssh.github.com]:443` host key with GitHub's published
>    fingerprints on first connect.
> 3. Clone with `git clone git@github.com:<owner>/<repo>.git /opt/infra`.
> 4. After setup, copy the key and config to `/home/<admin-user>/.ssh/` (mode
>    600, owned by `<admin-user>`) and delete root's copies.

### 4. Create env files

`docker compose` reads env files as the user running it, so `/etc/demos` and the
files in it belong to `<admin-user>` and are readable by nobody else:

```sh
sudo install -d -m 700 -o <admin-user> -g <admin-user> /etc/demos
install -m 600 /opt/infra/env/caddy.env.example /etc/demos/caddy.env
install -m 600 /opt/infra/env/waste-sorter.env.example /etc/demos/waste-sorter.env
cp /opt/infra/.env.example /opt/infra/.env
```

Edit `/etc/demos/caddy.env` and `/etc/demos/waste-sorter.env` as `<admin-user>`, and fill
in:

- `ACME_EMAIL`
- `APP_KEY` (`openssl rand -base64 32`)
- `MODEL_API_KEY`: the app refuses to start in production without it. For a
  keyless demo with simulated models, leave it empty and set
  `ALLOW_MOCK_MODELS=true` instead.

In `/opt/infra/.env`, set `WASTE_SORTER_TAG` to a specific version to pin the
image.

### 5. Upgrade and reboot

Install pending updates before starting services, and reboot if the kernel or
core libraries changed:

```sh
sudo apt update && sudo apt upgrade -y
[ -f /var/run/reboot-required ] && sudo reboot
```

After a reboot, log in again as `<admin-user>`.

### 6. Start

```sh
cd /opt/infra
docker compose pull
docker compose up -d
```

> **Private images?** The waste-sorter image is public, so no login is needed.
> If yours is private, first run `docker login ghcr.io -u <github-user>` as
> `<admin-user>` with a classic personal access token scoped to `read:packages`
> only. Docker stores it unencrypted in `~/.docker/config.json`, and it expires:
> renew it before then, or `docker compose pull` fails with `unauthorized`.

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
