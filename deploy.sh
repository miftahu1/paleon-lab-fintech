#!/usr/bin/env bash
# =============================================================================
# Paleon Fintech Test Site (Site 1) — Deployment Script
# Deploys website files to EC2 instance via SSH/rsync.
# Infrastructure must already be provisioned via Terraform.
#
# Usage:
#   ./deploy.sh [USER@HOST]
#   Example: ./deploy.sh ubuntu@3.12.34.56
#
# Required env vars (or passed as arg):
#   DEPLOY_HOST   - EC2 public IP or DNS
#   SSH_KEY       - path to SSH private key
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_ROOT="/var/www/paleon-fintech"
NGINX_CONF_NAME="paleon-fintech"

# Parse host argument or use env
if [[ $# -ge 1 ]]; then
  DEPLOY_TARGET="$1"
elif [[ -n "${DEPLOY_HOST:-}" ]]; then
  DEPLOY_TARGET="ubuntu@${DEPLOY_HOST}"
else
  echo "ERROR: No deployment target. Pass as arg (ubuntu@1.2.3.4) or set DEPLOY_HOST env." >&2
  echo "Usage: $0 ubuntu@HOST" >&2
  exit 1
fi

SSH_KEY="${SSH_KEY:-}"
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY")
else
  SSH_OPTS=()
fi

echo "==> Deploying Site 1 (Fintech) to: ${DEPLOY_TARGET}"

# --- Pre-flight checks -------------------------------------------------------
command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync required"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "ERROR: ssh required"; exit 1; }

# --- Step 1: Create remote directories --------------------------------------
echo "==> Creating remote directories..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" "sudo mkdir -p ${REMOTE_ROOT}/{main,app,api,dev} && echo created"

# --- Step 2: Sync website files ---------------------------------------------
echo "==> Syncing website files..."
rsync -avz --delete \
  --exclude='.git' \
  --exclude='terraform' \
  --exclude='*.md' \
  --exclude='.gitignore' \
  -e "ssh ${SSH_OPTS[*]}" \
  "${SCRIPT_DIR}/" "${DEPLOY_TARGET}:/tmp/fintech-site/"

# --- Step 3: Copy into web roots --------------------------------------------
echo "==> Placing files in web roots..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" bash -s <<EOF
set -e
sudo cp -r /tmp/fintech-site/index.html /tmp/fintech-site/css /tmp/fintech-site/js /tmp/fintech-site/static /tmp/fintech-site/about /tmp/fintech-site/services /tmp/fintech-site/solutions /tmp/fintech-site/resources /tmp/fintech-site/contact /tmp/fintech-site/.env ${REMOTE_ROOT}/main/
sudo cp -r /tmp/fintech-site/app/* ${REMOTE_ROOT}/app/
sudo cp -r /tmp/fintech-site/api/* ${REMOTE_ROOT}/api/
sudo cp -r /tmp/fintech-site/dev/* ${REMOTE_ROOT}/dev/
sudo chown -R www-data:www-data ${REMOTE_ROOT}
# Set directories to 755, files to 644 (not all executable)
sudo find ${REMOTE_ROOT} -type d -exec chmod 755 {} \;
sudo find ${REMOTE_ROOT} -type f -exec chmod 644 {} \;
echo "files placed"
EOF

# --- Step 4: Deploy nginx config --------------------------------------------
echo "==> Deploying nginx config..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" bash -s <<EOF
set -e
sudo cp /tmp/fintech-site/nginx.conf /etc/nginx/sites-available/${NGINX_CONF_NAME}
if [ ! -L /etc/nginx/sites-enabled/${NGINX_CONF_NAME} ]; then
  sudo ln -s /etc/nginx/sites-available/${NGINX_CONF_NAME} /etc/nginx/sites-enabled/
fi
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "nginx deployed"
EOF

# --- Step 5: Deploy dummy postgres listener ---------------------------------
echo "==> Deploying dummy postgres listener (port 5432)..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" bash -s <<EOF
set -e
sudo cp /tmp/fintech-site/dummy-postgres.listener.service /etc/systemd/system/dummy-postgres.service
sudo systemctl daemon-reload
sudo systemctl enable dummy-postgres
sudo systemctl restart dummy-postgres
sudo systemctl status dummy-postgres --no-pager | head -3
echo "listener deployed"
EOF

echo ""
echo "==> Deployment complete."
echo "==> Next: run ./validate.sh OR test externally with Paleon scanner."
echo "==> See expected.yaml for what should be detected."
