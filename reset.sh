#!/usr/bin/env bash
# =============================================================================
# Paleon Fintech Test Site (Site 1) — Reset Script
# Stops services, clears web roots, redeploys from git, restarts services.
# Use after content changes or to restore clean state.
#
# Usage:
#   ./reset.sh [USER@HOST]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_ROOT="/var/www/paleon-fintech"
NGINX_CONF_NAME="paleon-fintech"

if [[ $# -ge 1 ]]; then
  DEPLOY_TARGET="$1"
elif [[ -n "${DEPLOY_HOST:-}" ]]; then
  DEPLOY_TARGET="ubuntu@${DEPLOY_HOST}"
else
  echo "ERROR: No target. Pass ubuntu@HOST or set DEPLOY_HOST." >&2
  exit 1
fi

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "==> Resetting Site 1 (Fintech) on: ${DEPLOY_TARGET}"

# --- Stop services -----------------------------------------------------------
echo "==> Stopping services..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" "sudo systemctl stop nginx dummy-postgres 2>/dev/null; echo stopped"

# --- Clear web roots ---------------------------------------------------------
echo "==> Clearing web roots..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" "sudo rm -rf ${REMOTE_ROOT}/* && echo cleared"

# --- Re-sync from local ------------------------------------------------------
echo "==> Re-syncing files..."
rsync -avz --delete \
  --exclude='.git' --exclude='terraform' --exclude='*.md' --exclude='.gitignore' \
  -e "ssh ${SSH_OPTS[*]}" \
  "${SCRIPT_DIR}/" "${DEPLOY_TARGET}:/tmp/fintech-site/"

ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" bash -s <<EOF
set -e
sudo mkdir -p ${REMOTE_ROOT}/{main,app,api,dev}
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

# --- Restart services --------------------------------------------------------
echo "==> Restarting services..."
ssh "${SSH_OPTS[@]}" "$DEPLOY_TARGET" bash -s <<EOF
set -e
sudo systemctl restart dummy-postgres
sudo nginx -t
sudo systemctl restart nginx
EOF

echo ""
echo "==> Reset complete. Verify with: ./validate.sh"
