#!/usr/bin/env bash
# =============================================================================
# Paleon Fintech Test Site (Site 1) — Local Validation Script
# Verifies local files & structure match expected.yaml ground truth.
#
# This is a PRE-DEPLOYMENT check. Final validation is done by the Paleon
# external scanner against the live domain.
#
# Usage:
#   ./validate.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

green() { printf '\033[0;32m[PASS]\033[0m %s\n' "$1"; }
red()   { printf '\033[0;31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
info()  { printf '\033[0;34m[INFO]\033[0m %s\n' "$1"; }

echo "=================================================="
echo " Paleon Fintech Test Site (Site 1) — Validation"
echo "=================================================="
echo ""

# --- 1. Required files present ----------------------------------------------
info "Checking required files..."
REQUIRED=(
  "index.html" "expected.yaml" "nginx.conf" "README.md"
  "ARCHITECTURE.md" "DEPLOYMENT.md" ".gitignore"
  "css/main.css" "js/main.js"
  "static/brand-mark.svg" "static/favicon.svg" "static/hero-dashboard.svg"
  "about/index.html" "services/index.html" "solutions/index.html"
  "resources/index.html" "contact/index.html"
  "app/index.html" "api/index.html" "api/swagger.json" "dev/index.html"
  ".env" "subdomain-takeover-indicator.txt" "dummy-postgres.listener.service"
  "deploy.sh" "reset.sh" "validate.sh"
  "terraform/main.tf" "terraform/variables.tf" "terraform/outputs.tf" "terraform/README.md"
)
for f in "${REQUIRED[@]}"; do
  if [[ -f "$SCRIPT_DIR/$f" ]]; then
    green "exists: $f"
  else
    red "missing: $f"
  fi
done

# --- 2. .env contains fake placeholders only --------------------------------
info "Checking .env contains fake placeholders..."
if grep -q "APP_ENV=development" "$SCRIPT_DIR/.env" && \
   grep -q "DEMO_KEY=placeholder-demo-key" "$SCRIPT_DIR/.env" && \
   grep -q "AWS_REFERENCE=arn:aws:example:eu-west-2:123456789012:example-resource" "$SCRIPT_DIR/.env"; then
  green ".env has fake placeholders (development, placeholder key, example ARN)"
else
  red ".env missing expected fake placeholders"
fi

# Ensure no real-looking secrets
if grep -qiE "AKIA[0-9A-Z]{16}|sk_live_|pk_live_" "$SCRIPT_DIR/.env"; then
  red ".env contains real-looking secret patterns (AKIA live keys)"
else
  green ".env has no real-looking AWS/Stripe live keys"
fi

# --- 3. swagger.json is valid JSON ------------------------------------------
info "Validating swagger.json..."
if command -v node >/dev/null 2>&1; then
  if node -e "const j=require('./api/swagger.json'); if(j.openapi!=='3.1.0') process.exit(1); if(!j.paths||Object.keys(j.paths).length===0) process.exit(1);" 2>/dev/null; then
    green "swagger.json valid OpenAPI 3.1 with paths"
  else
    red "swagger.json invalid or not OpenAPI 3.1"
  fi
elif command -v python3 >/dev/null 2>&1; then
  if python3 -c "import json,sys; d=json.load(open('$SCRIPT_DIR/api/swagger.json')); assert d['openapi']=='3.1.0'; assert len(d['paths'])>0" 2>/dev/null; then
    green "swagger.json valid OpenAPI 3.1 with paths"
  else
    red "swagger.json invalid or not OpenAPI 3.1"
  fi
else
  info "node/python3 not available; skipping JSON validation"
fi

# --- 4. nginx.conf has 4 server blocks for HTTPS ----------------------------
info "Checking nginx.conf virtual hosts..."
for host in "paleon-lab-fintech.co.uk" "app.paleon-lab-fintech.co.uk" "api.paleon-lab-fintech.co.uk" "dev.paleon-lab-fintech.co.uk"; do
  if grep -q "server_name.*$host" "$SCRIPT_DIR/nginx.conf"; then
    green "vhost configured: $host"
  else
    red "vhost missing: $host"
  fi
done

# --- 5. HSTS intentionally omitted on app & dev -----------------------------
info "Checking HSTS omission..."
if grep -q "app.paleon-lab-fintech.co.uk" "$SCRIPT_DIR/nginx.conf"; then
  # Find app server block and check no HSTS
  app_block=$(awk '/server_name app.paleon-lab-fintech.co.uk;/{f=1} f{print} /^}/{if(f)exit}' "$SCRIPT_DIR/nginx.conf")
  if echo "$app_block" | grep -qi "Strict-Transport-Security"; then
    red "HSTS present on app host (should be omitted)"
  else
    green "HSTS omitted on app host (intentional)"
  fi
else
  red "app host block not found"
fi

# --- 6. Outdated Server header on dev ---------------------------------------
info "Checking outdated Server header on dev host..."
if grep -q "more_set_headers 'Server: nginx/1.14.0'" "$SCRIPT_DIR/nginx.conf"; then
  green "dev host sets Server: nginx/1.14.0 (outdated indicator)"
else
  red "dev host missing outdated Server header"
fi

# --- 7. Clean URL routing ----------------------------------------------------
info "Checking clean URL routing (try_files)..."
if grep -q "try_files \$uri \$uri/index.html" "$SCRIPT_DIR/nginx.conf"; then
  green "try_files clean URL routing present"
else
  red "try_files routing missing"
fi

# --- 8. .env exposure location block ----------------------------------------
info "Checking .env exposure in nginx.conf..."
if grep -q "location = /.env" "$SCRIPT_DIR/nginx.conf"; then
  green ".env exposure location block present"
else
  red ".env exposure location block missing"
fi

# --- 9. swagger.json exposure ------------------------------------------------
info "Checking swagger.json exposure in nginx.conf..."
if grep -q "location = /swagger.json" "$SCRIPT_DIR/nginx.conf"; then
  green "swagger.json exposure location block present"
else
  red "swagger.json exposure missing"
fi

# --- 10. Port 5432 dummy listener service -----------------------------------
info "Checking dummy postgres listener service..."
if grep -q "TCP-LISTEN:5432" "$SCRIPT_DIR/dummy-postgres.listener.service"; then
  green "dummy listener binds port 5432"
else
  red "dummy listener not bound to 5432"
fi
if grep -q "ExecStart=/usr/bin/socat" "$SCRIPT_DIR/dummy-postgres.listener.service"; then
  green "uses socat (no real PostgreSQL)"
else
  red "dummy listener does not use socat"
fi


# --- 11. Subdomain takeover safe indicators --------------------------------
info "Checking subdomain-takeover safe indicators..."
if grep -q "s3-website-eu-west-1.amazonaws.com" "$SCRIPT_DIR/subdomain-takeover-indicator.txt" && \
   grep -q "herokudns.com" "$SCRIPT_DIR/subdomain-takeover-indicator.txt"; then
  green "two safe CNAME indicators documented"
else
  red "safe CNAME indicators not fully documented"
fi

# --- 12. Security group ports in terraform ---------------------------------
info "Checking terraform security group ports..."
if grep -q "5432" "$SCRIPT_DIR/terraform/main.tf" && \
   grep -q "22" "$SCRIPT_DIR/terraform/main.tf"; then
  green "terraform SG includes 5432 and 22"
else
  red "terraform SG missing 5432 or 22"
fi

# --- 13. Forbidden ports NOT exposed ----------------------------------------
info "Checking forbidden ports are NOT in SG ingress..."
for port in 3306 3389 445 23 25 6379 27017; do
  if grep -q "from_port.*=.*$port\|= $port" "$SCRIPT_DIR/terraform/main.tf"; then
    red "forbidden port $port found in SG (should not be exposed)"
  else
    green "port $port not exposed (good)"
  fi
done

# --- 14. expected.yaml must_not_flag present --------------------------------
info "Checking expected.yaml must_not_flag patterns..."
for pat in "real-aws-credentials" "real-stripe-keys" "postgresql-service" "subdomain-takeover-exploitable" "confirmed-cve-nginx"; do
  if grep -q "$pat" "$SCRIPT_DIR/expected.yaml"; then
    green "must_not_flag: $pat"
  else
    red "must_not_flag missing: $pat"
  fi
done

# --- 15. no stale module package or loader mismatches ----------------------
info "Checking Headers-More package and module config usage..."
if grep -q "libnginx-mod-http-headers-more-filter" "$SCRIPT_DIR/nginx.conf" && ! grep -Eq "^[[:space:]]*load_module[[:space:]]" "$SCRIPT_DIR/nginx.conf"; then
  green "Headers-More package documented and site-level load_module removed"
else
  red "Headers-More package documentation or module loader is inconsistent"
fi

# --- 16. .gitignore protects secrets ---------------------------------------
info "Checking .gitignore protects secrets..."
for pat in "*.key" "terraform.tfstate" ".env.real"; do
  if grep -q "$pat" "$SCRIPT_DIR/.gitignore"; then
    green ".gitignore excludes: $pat"
  else
    red ".gitignore missing: $pat"
  fi
done

# --- 16. expected.yaml counts verification ------------------------------------
info "Checking expected.yaml counts match actual entries..."
if command -v python3 >/dev/null 2>&1; then
  python3 <<'PYEOF'
import yaml, sys
with open('expected.yaml') as f:
    d = yaml.safe_load(f)
sd = len(d.get('scanner_detections', []))
po = len(d.get('positive_observations', []))
fg = len(d.get('false_positive_guardrails', []))
total = sd + po + fg
print(f"  scanner_detections: {sd}")
print(f"  positive_observations: {po}")
print(f"  false_positive_guardrails: {fg}")
print(f"  total: {total}")
# Verify against validation_summary
vs = d.get('validation_summary', {})
if vs.get('scanner_detections') == sd and vs.get('positive_observations') == po and vs.get('false_positive_guardrails') == fg and vs.get('total_test_cases') == total:
    print("  Validation summary matches actual counts!")
    sys.exit(0)
else:
    print("  MISMATCH: validation_summary does not match actual counts!")
    print(f"  validation_summary: {vs}")
    sys.exit(1)
PYEOF
  if [[ $? -eq 0 ]]; then
    green "expected.yaml counts verified programmatically"
  else
    red "expected.yaml count mismatch"
  fi
else
  info "python3 not available; skipping expected.yaml count verification"
fi

# --- Summary -----------------------------------------------------------------
echo ""
echo "=================================================="
echo " Validation Summary"
echo "=================================================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "\033[0;32m All checks passed ($PASS passed).\033[0m"
  echo ""
  echo " Next steps:"
  echo "   1. terraform init && terraform apply"
  echo "   2. Configure DNS (A + CNAME + TXT records)"
  echo "   3. ./deploy.sh ubuntu@ELASTIC_IP"
  echo "   4. Run Paleon external scanner → compares to expected.yaml"
  exit 0
else
  echo -e "\033[0;31m $FAIL check(s) failed.\033[0m"
  exit 1
fi
