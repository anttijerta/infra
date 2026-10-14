# AGENTS.md

This repo configures one UpCloud server (Ubuntu LTS, Helsinki) that runs public
demos with Docker Compose behind Caddy.

## Rules

- You never connect to the server. The owner runs every command there themselves.
  Write scripts and instructions; do not run them against the server.
- No secrets, IP addresses or tokens in the repo. Real values live only in env
  files on the server (`/etc/demos/*.env`). Commit `*.env.example` files with
  empty or placeholder values. A gitleaks pre-commit hook (`.githooks/pre-commit`)
  scans staged changes.
- One server, Docker Compose. No Kubernetes, no IaC tools (Terraform, Ansible, etc.).
- Pin image versions. Explain any security trade-off in a comment next to it.
- Code, comments and docs in English. Small commits, one concern each.
