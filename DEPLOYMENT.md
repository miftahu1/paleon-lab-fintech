# Paleon Fintech Test Site (Site 1) — Deployment Guide

**Updated:** 2026-08-30  
**Architecture:** Single EC2 t4g.nano + Nginx (4 vhosts) + Dummy TCP Listener

---

## Overview

This guide covers complete deployment of Site 1 to AWS infrastructure. The deployment uses a single minimal EC2 instance (t4g.nano) running Ubuntu 26.04 LTS ARM64 in eu-west-2 (London).

All values in this guide use placeholder syntax (e.g., `[ELASTIC_IP]`, `[ADMIN_IP]`) that must be replaced with real values during deployment.

---

## Prerequisites

- [ ] AWS account with console/CLI access
- [ ] Domain registered: `paleon-lab-fintech.co.uk`
- [ ] DNS provider access (Route 53 or external registrar)
- [ ] SSH keypair created in AWS
- [ ] Admin IP address for SSH restriction
- [ ] Terraform ≥ 1.5 installed locally

---

## Step 1: Launch Infrastructure (Terraform)

### 1.1 Configure Variables

Edit `terraform/variables.tf` and set:

```hcl
variable "domain_name" {
  default = "paleon-lab-fintech.co.uk"
}

variable "admin_ip" {
  default = "YOUR_ADMIN_IP/32"  # e.g., "203.0.113.45/32"
}

variable "region" {
  default = "eu-west-2"
}
```

### 1.2 Deploy

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 1.3 Capture Outputs

```bash
terraform output elastic_ip
# Note: e.g., 3.12.34.56

terraform output instance_id
terraform output ssh_command
```

---

## Step 2: Configure DNS

At your DNS provider, create these records:

```dns
# A Records (all → Elastic IP)
paleon-lab-fintech.co.uk      IN A    [ELASTIC_IP]
www.paleon-lab-fintech.co.uk  IN A    [ELASTIC_IP]
app.paleon-lab-fintech.co.uk  IN A    [ELASTIC_IP]
api.paleon-lab-fintech.co.uk  IN A    [ELASTIC_IP]
dev.paleon-lab-fintech.co.uk  IN A    [ELASTIC_IP]

# Subdomain-takeover indicators (CNAME → non-existent targets)
staging.paleon-lab-fintech.co.uk  IN CNAME  staging.paleon-lab-fintech.co.uk.s3-website-eu-west-1.amazonaws.com.
dev-old.paleon-lab-fintech.co.uk  IN CNAME  paleon-lab-old-env.herokudns.com.

# SPF (weak - intentional)
paleon-lab-fintech.co.uk      IN TXT  "v=spf1 include:_spf.google.com ~all"

# DMARC (p=none - intentional)
_dmarc.paleon-lab-fintech.co.uk  IN TXT  "v=DMARC1; p=none; rua=mailto:dmarc@paleon-lab-fintech.co.uk"
```

**Important:** Do NOT enable DNSSEC (intentional omission for testing). The safe takeover indicator is a lab-only DNS indicator and must never be described as a confirmed takeover.

### Wait for Propagation

```bash
dig paleon-lab-fintech.co.uk +short
dig app.paleon-lab-fintech.co.uk +short
dig api.paleon-lab-fintech.co.uk +short
dig dev.paleon-lab-fintech.co.uk +short
dig _dmarc.paleon-lab-fintech.co.uk TXT +short
dig staging.paleon-lab-fintech.co.uk CNAME +short
```

---

## Step 3: Initial Server Setup

### 3.1 Connect

```bash
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@[ELASTIC_IP]
```

### 3.2 Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### 3.3 Install Packages

```bash
sudo apt install -y nginx libnginx-mod-http-headers-more-filter socat openssl git
```

On Ubuntu, the package installs the module configuration under `/etc/nginx/modules-enabled/`. The normal nginx `http` context then exposes `more_set_headers` without a site-level `load_module` directive.

Verify headers-more module:

```bash
dpkg -l | grep libnginx-mod-http-headers-more-filter
ls /etc/nginx/modules-enabled | grep headers-more
```

---

## Step 4: Generate TLS Certificate

```bash
sudo openssl req -x509 \
  -newkey rsa:2048 \
  -keyout /etc/ssl/private/paleon-fintech.key \
  -out /etc/ssl/certs/paleon-fintech.crt \
  -days 3650 \
  -nodes \
  -subj "/C=GB/ST=Greater London/L=London/O=Tessera Financial Ltd/CN=paleon-lab-fintech.co.uk" \
  -addext "subjectAltName=DNS:paleon-lab-fintech.co.uk,DNS:www.paleon-lab-fintech.co.uk,DNS:app.paleon-lab-fintech.co.uk,DNS:api.paleon-lab-fintech.co.uk,DNS:dev.paleon-lab-fintech.co.uk"

sudo chmod 600 /etc/ssl/private/paleon-fintech.key
sudo chmod 644 /etc/ssl/certs/paleon-fintech.crt

# Verify
sudo openssl x509 -in /etc/ssl/certs/paleon-fintech.crt -text -noout | grep -A1 "Subject Alternative Name"
```

---

## Step 5: Deploy Website Files

### 5.1 Create Directories

```bash
sudo mkdir -p /var/www/paleon-fintech/main
sudo mkdir -p /var/www/paleon-fintech/app
sudo mkdir -p /var/www/paleon-fintech/api
sudo mkdir -p /var/www/paleon-fintech/dev
```

### 5.2 Copy Files

```bash
# From local machine
rsync -avz --exclude='.git' --exclude='terraform' --exclude='*.md' \
  -e "ssh -i ~/.ssh/YOUR_KEY.pem" \
  ./ ubuntu@[ELASTIC_IP]:/tmp/fintech-site/

# On server
sudo cp -r /tmp/fintech-site/index.html /tmp/fintech-site/css /tmp/fintech-site/js /tmp/fintech-site/static /tmp/fintech-site/about /tmp/fintech-site/services /tmp/fintech-site/solutions /tmp/fintech-site/resources /tmp/fintech-site/contact /tmp/fintech-site/.env /var/www/paleon-fintech/main/
sudo cp -r /tmp/fintech-site/app/* /var/www/paleon-fintech/app/
sudo cp -r /tmp/fintech-site/api/* /var/www/paleon-fintech/api/
sudo cp -r /tmp/fintech-site/dev/* /var/www/paleon-fintech/dev/
```

### 5.3 Set Permissions

```bash
sudo chown -R www-data:www-data /var/www/paleon-fintech
# Set directories to 755, files to 644 (not all executable)
sudo find /var/www/paleon-fintech -type d -exec chmod 755 {} \;
sudo find /var/www/paleon-fintech -type f -exec chmod 644 {} \;
```

---

## Step 6: Configure Nginx

### 6.1 Deploy Config

```bash
sudo cp /tmp/fintech-site/nginx.conf /etc/nginx/sites-available/paleon-fintech
sudo ln -s /etc/nginx/sites-available/paleon-fintech /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
```
Do not add a `load_module` directive inside the site config. On Ubuntu, the package installation creates the loader automatically in `/etc/nginx/modules-enabled/`.
### 6.2 Test

```bash
sudo nginx -t
# Expected: "syntax is ok" and "test is successful"
```

### 6.3 Reload

```bash
sudo systemctl reload nginx
sudo systemctl status nginx
```

---

## Step 7: Dummy TCP Listener (Port 5432)

### 7.1 Create Service

```bash
sudo cp /tmp/fintech-site/dummy-postgres.listener.service /etc/systemd/system/dummy-postgres.service
sudo systemctl daemon-reload
sudo systemctl enable dummy-postgres
sudo systemctl start dummy-postgres
sudo systemctl status dummy-postgres
```

### 7.2 Verify

```bash
# Local check
sudo ss -tlnp | grep 5432
# Should show: LISTEN 0 5 :::5432
```

---

## Step 8: Verification

### 8.1 From Server

```bash
# Main site routes
for path in / /about /services /solutions /resources /contact; do
  echo "=== $path ==="
  curl -s -o /dev/null -w "%{http_code}" https://localhost$path
done

# Verify .env exposed
curl -s https://localhost/.env | head -5

# Verify swagger.json
curl -s https://localhost/swagger.json --resolve api.paleon-lab-fintech.co.uk:443:127.0.0.1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('openapi:', d['openapi'])"

# Verify HSTS missing on app host
curl -sI https://localhost/ --resolve app.paleon-lab-fintech.co.uk:443:127.0.0.1 | grep -i strict-transport
# Should return nothing

# Verify outdated server header on dev host
curl -sI https://localhost/ --resolve dev.paleon-lab-fintech.co.uk:443:127.0.0.1 | grep -i server
# Should show: Server: nginx/1.14.0
```

### 8.2 From External Machine

```bash
# Port 5432 reachability
nc -zv paleon-lab-fintech.co.uk 5432
# Should show: succeeded

# Or nmap
nmap -p 5432 paleon-lab-fintech.co.uk

# Confirm risky ports NOT exposed
nmap -p 3306,3389,445,23,25,6379,27017 paleon-lab-fintech.co.uk
# All should be: filtered/closed

# Certificate validity (should be VALID, not expired)
echo | openssl s_client -connect paleon-lab-fintech.co.uk:443 2>/dev/null | openssl x509 -noout -dates
```

### 8.3 Run Validation Script

```bash
./validate.sh
```

---

## Step 9: Final Checklist

- [ ] EC2 instance running in eu-west-2
- [ ] Elastic IP associated
- [ ] Security group: 80, 443, 5432 public; 22 admin-only
- [ ] DNS A records for 5 hosts
- [ ] DNS CNAMEs for staging & dev-old
- [ ] DNS TXT: SPF (~all), DMARC (p=none)
- [ ] DNSSEC disabled
- [ ] Nginx + headers-more installed
- [ ] All 4 vhosts configured
- [ ] Self-signed cert valid (10 years)
- [ ] Website files deployed
- [ ] .env accessible at main root
- [ ] swagger.json valid OpenAPI 3.1
- [ ] App host: no HSTS
- [ ] Dev host: Server nginx/1.14.0, TLS 1.0/1.1
- [ ] Dummy postgres service running
- [ ] Port 5432 reachable (TCP)
- [ ] Ports 3306/3389/445/23/25/6379/27017 NOT reachable
- [ ] validate.sh passes

---

## Maintenance

### Update Content

```bash
# RSync new files, reload nginx
sudo rsync -avz ./ ubuntu@[ELASTIC_IP]:/tmp/fintech-site/
# Copy changed files, then:
sudo systemctl reload nginx
```

### View Logs

```bash
sudo tail -f /var/log/nginx/paleon-fintech-*.log
sudo journalctl -u dummy-postgres -f
```

### Reset

```bash
./reset.sh
```

---

## Troubleshooting

### Issue: Port 5432 not reachable

```bash
sudo systemctl status dummy-postgres
sudo ss -tlnp | grep 5432
# Check security group allows 5432 from 0.0.0.0/0
```

### Issue: more_set_headers not working

```bash
dpkg -l | grep libnginx-mod-http-headers-more-filter
# If missing: sudo apt install libnginx-mod-http-headers-more-filter
sudo nginx -t && sudo systemctl reload nginx
```

### Issue: Certificate errors

```bash
sudo openssl x509 -in /etc/ssl/certs/paleon-fintech.crt -noout -dates
# Ensure Not After is in the future (valid cert)
```

### Issue: Routes 404

```bash
sudo nginx -t
ls -la /var/www/paleon-fintech/main/about/
sudo tail -n 50 /var/log/nginx/paleon-fintech-error.log
```

---

## Teardown

```bash
cd terraform
terraform destroy
# Confirm with 'yes'

# Remove DNS records at registrar
```

---

## Cost Estimate

- t4g.nano: ~$3/month
- Elastic IP (attached): $0
- 8 GB gp3: ~$0.80/month
- Data transfer: ~$1-2/month
- **Total: ~$5-6/month**

---

## Security Notes

- This is a TEST ENVIRONMENT with INTENTIONAL weaknesses
- Do NOT use for real traffic or real data
- Port 5432 listener provides no database functionality
- All credentials in .env are FAKE
- Certificate is self-signed (valid but untrusted by browsers)
- Isolated from production Paleon infrastructure
- SSH restricted to admin IP only

---

**Deployment Status:** Ready  
**Estimated Time:** 2-3 hours  
**Infrastructure:** Single t4g.nano