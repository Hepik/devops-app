#!/usr/bin/env bash
# One-time EC2 setup. Run manually on a fresh instance (or as cloud-init
# user-data). Terraform will automate this at Крок 3 of the task.
set -euo pipefail

# --- Docker Engine + Compose plugin (Amazon Linux 2023 / Ubuntu compatible via apt fallback) ---
if command -v dnf >/dev/null 2>&1; then
  sudo dnf update -y
  sudo dnf install -y docker
  sudo systemctl enable --now docker
  DOCKER_COMPOSE_PLUGIN_DIR=/usr/local/lib/docker/cli-plugins
  sudo mkdir -p "$DOCKER_COMPOSE_PLUGIN_DIR"
  sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o "$DOCKER_COMPOSE_PLUGIN_DIR/docker-compose"
  sudo chmod +x "$DOCKER_COMPOSE_PLUGIN_DIR/docker-compose"
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io docker-compose-plugin
  sudo systemctl enable --now docker
fi

# Let the deploy user run docker without sudo
sudo usermod -aG docker "$(whoami)"

# Deploy directory the CI pipeline scp's docker-compose.prod.yml into
sudo mkdir -p /opt/devops-app
sudo chown "$(whoami)":"$(whoami)" /opt/devops-app

echo "Done. Next: copy .env.prod.example to /opt/devops-app/.env, fill in real"
echo "values, then let the CI pipeline push the first deploy."
