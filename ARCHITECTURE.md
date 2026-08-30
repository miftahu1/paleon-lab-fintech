# Paleon Fintech Test Site (Site 1) — Architecture

**Domain:** `paleon-lab-fintech.co.uk`  
**Updated:** 2026-08-30  
**Status:** Defined — ready for implementation

---

## Executive Summary

This document describes the architecture for Site 1 — a fictional UK fintech/payments SME website with deliberately planted scanner test conditions across 4 virtual hosts and supporting infrastructure.

Unlike Site 4 (Northbridge), Site 1 does **not** use an expired TLS certificate and instead focuses on:
- Application-level findings (headers, exposed files, API specs)
- Legacy component indicators (outdated Server header, legacy TLS)
- Network-level findings (port 5432 dummy listener)
- DNS findings (DMARC, SPF, DNSSEC, subdomain-takeover indicators)

---

## Architecture Analysis

### What Does NOT Require EC2/Nginx

These findings are achievable via DNS configuration only:

✅ **DMARC p=none** — DNS TXT record  
✅ **Weak SPF (~all)** — DNS TXT record  
✅ **DNSSEC disabled** — DNS configuration (absence of DS records)  
✅ **Subdomain-takeover indicators** — CNAME records to non-existent targets

### What DOES Require HTTP/HTTPS Infrastructure

These findings need actual HTTP(S) endpoints with custom headers/content:

⚠️ **Missing HSTS on app host** — Requires nginx config without HSTS  
⚠️ **Missing HSTS on dev host** — Requires nginx config without HSTS  
⚠️ **Outdated Server header (nginx/1.14.0)** — Requires `more_set_headers` on dev host  
⚠️ **Legacy TLS protocols (1.0/1.1)** — Requires nginx `ssl_protocols` config on dev host  
⚠️ **Exposed /.env file** — Requires nginx location block serving file  
⚠️ **Exposed /swagger.json** — Requires nginx location block serving JSON  
⚠️ **Clean URL routing** — Requires nginx `try_files` with directory index

### What Requires TCP Listener

⚠️ **Port 5432 reachable** — Requires dummy TCP listener (socat), NOT PostgreSQL; intended as a safe non-intrusive scanner indicator only.

### What Requires TLS Certificate

⚠️ **Valid self-signed certificate** — Self-signed cert for all 4 HTTPS hosts (NOT expired)

---

## Recommended Architecture: Single EC2 t4g.nano

```
┌─────────────────────────────────────────────────────────────────┐
│                    Internet                                     │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              AWS Elastic IP (static)                            │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│         Security Group                                          │
│  • TCP 80    → 0.0.0.0/0   (HTTP redirect)                     │
│  • TCP 443   → 0.0.0.0/0   (HTTPS)                              │
│  • TCP 5432  → 0.0.0.0/0   (Dummy TCP listener port - INTENTIONAL; no PostgreSQL)│
│  • TCP 22    → <admin IP>/32 (SSH management)                  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  EC2 t4g.nano (Ubuntu 26.04 LTS ARM64, eu-west-2)              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Nginx (4 virtual hosts)                                 │   │
│  │  • paleon-lab-fintech.co.uk (main)                      │   │
│  │  • app.paleon-lab-fintech.co.uk (no HSTS)               │   │
│  │  • api.paleon-lab-fintech.co.uk (swagger.json)          │   │
│  │  • dev.paleon-lab-fintech.co.uk (old Server, TLS 1.0/1.1)│   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Dummy TCP Listener (systemd service)                    │   │
│  │  • Port 5432: socat TCP-LISTEN:5432,reuseaddr,fork      │   │
│  │    EXEC:/bin/true                                       │   │
│  │  • No PostgreSQL protocol, no data, no auth             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Self-signed TLS certificate                             │   │
│  │  • CN: paleon-lab-fintech.co.uk                         │   │
│  │  • SANs: *.paleon-lab-fintech.co.uk                     │   │
│  │  • Valid (NOT expired)                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Infrastructure Components

### AWS EC2 Instance

| Property | Value |
|----------|-------|
| **Instance Type** | t4g.nano (2 vCPU, 0.5 GB RAM) — smallest ARM64 |
| **AMI** | Ubuntu 26.04 LTS ARM64 (Canonical) |
| **Region** | eu-west-2 (London) |
| **Storage** | 8 GB gp3 (minimum) |
| **Elastic IP** | Yes (static IP for DNS) |
| **IAM Role** | None required (no AWS API calls from instance) |

### Security Group

```
Inbound Rules:
├── TCP 80    from 0.0.0.0/0      (HTTP → redirects to HTTPS)
├── TCP 443   from 0.0.0.0/0      (HTTPS for all 4 hosts)
├── TCP 5432  from 0.0.0.0/0      (INTENTIONAL - dummy listener)
└── TCP 22    from <ADMIN_IP>/32  (SSH - RESTRICTED)

Outbound Rules:
└── All traffic (for apt updates, DNS resolution)
```

**Critical:** Port 22 MUST be restricted to administrator IP only. Never open to 0.0.0.0/0.

### Software Stack

| Component | Version/Package | Purpose |
|-----------|----------------|---------|
| Nginx | Ubuntu default (1.24+) | Web server, 4 vhosts |
| libnginx-mod-http-headers-more-filter | Ubuntu package | `more_set_headers` for custom Server header |
| socat | Ubuntu package | Dummy TCP listener on 5432 |
| openssl | Ubuntu package | Self-signed certificate generation |
| git | Ubuntu package | Deploy from repository |

---

## TLS Certificate Strategy

### Requirements
- Single certificate covering all 4 HTTPS hosts
- Valid (NOT expired) — unlike Site 4
- Self-signed (no Let's Encrypt dependency)
- SHA-256, RSA 2048-bit minimum

### Implementation

```bash
# Generate self-signed certificate valid for 10 years
sudo openssl req -x509 \
  -newkey rsa:2048 \
  -keyout /etc/ssl/private/paleon-fintech.key \
  -out /etc/ssl/certs/paleon-fintech.crt \
  -days 3650 \
  -nodes \
  -subj "/C=GB/ST=Greater London/L=London/O=Tessera Financial Ltd/CN=paleon-lab-fintech.co.uk" \
  -addext "subjectAltName=DNS:paleon-lab-fintech.co.uk,DNS:www.paleon-lab-fintech.co.uk,DNS:app.paleon-lab-fintech.co.uk,DNS:api.paleon-lab-fintech.co.uk,DNS:dev.paleon-lab-fintech.co.uk"

# Permissions
sudo chmod 600 /etc/ssl/private/paleon-fintech.key
sudo chmod 644 /etc/ssl/certs/paleon-fintech.crt
```

**Why not Let's Encrypt?**
- Test environment — no need for public trust
- Self-signed gives full control over validity period
- No rate limits, no renewal automation needed
- Certificate is NOT expired (Site 1 requirement)

---

## Port 5432 Dummy Listener

### What It Does

Opens TCP port 5432 and accepts connections but provides **no PostgreSQL functionality**.

### Implementation (systemd service)

```ini
# /etc/systemd/system/dummy-postgres.service
[Unit]
Description=Dummy TCP Listener on Port 5432 for Paleon Testing
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:5432,reuseaddr,fork EXEC:/bin/true
Restart=always
RestartSec=5
User=nobody
Group=nogroup
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
LimitNOFILE=1024
LimitNPROC=64

[Install]
WantedBy=multi-user.target
```

### What Scanner Sees

- TCP connection to port 5432 succeeds (SYN → SYN-ACK)
- Connection accepted then immediately closed
- No PostgreSQL banner, no authentication prompt, no protocol negotiation
- Scanner reports: "Port 5432 open/reachable"

### Security

- Runs as `nobody:nogroup` (unprivileged)
- No authentication mechanism
- No remote execution capability
- No PostgreSQL protocol implementation
- Simply accepts and closes connections
- Hardened systemd sandbox

---

## Outdated Component Disclosure (Dev Host)

### Current Implementation

Nginx on dev host uses `more_set_headers` to explicitly set:

```
Server: nginx/1.14.0
```

nginx 1.14.0 reached **End of Life on 2019-10-01**.

### Why This Approach

- Controllable: exact version string set in config
- No need to install old nginx binary
- Works with any nginx version
- Requires Ubuntu `libnginx-mod-http-headers-more-filter` package; the module is auto-loaded by the packaged config under `/etc/nginx/modules-enabled/` on Ubuntu 26.04 LTS.

### Legacy TLS on Dev Host

```nginx
ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
```

TLS 1.0 and 1.1 are deprecated (RFC 8996, 2021). This is a configuration-level indicator only.

---

## DNS Configuration

All records configured at domain registrar:

```dns
# A Records (all point to Elastic IP)
paleon-lab-fintech.co.uk          IN A    [ELASTIC_IP]
www.paleon-lab-fintech.co.uk      IN A    [ELASTIC_IP]
app.paleon-lab-fintech.co.uk      IN A    [ELASTIC_IP]
api.paleon-lab-fintech.co.uk      IN A    [ELASTIC_IP]
dev.paleon-lab-fintech.co.uk      IN A    [ELASTIC_IP]

# Subdomain-takeover indicators (CNAME to non-existent targets)
staging.paleon-lab-fintech.co.uk  IN CNAME  staging.paleon-lab-fintech.co.uk.s3-website-eu-west-1.amazonaws.com.
dev-old.paleon-lab-fintech.co.uk  IN CNAME  paleon-lab-old-env.herokudns.com.

# SPF (weak - intentional)
paleon-lab-fintech.co.uk          IN TXT  "v=spf1 include:_spf.google.com ~all"

# DMARC (p=none - intentional)
_dmarc.paleon-lab-fintech.co.uk   IN TXT  "v=DMARC1; p=none; rua=mailto:dmarc@paleon-lab-fintech.co.uk"

# DNSSEC: DO NOT ENABLE (intentional)
```

### Safety of Subdomain Indicators

Both CNAME targets are **synthetically constructed** and **cannot be claimed**:

1. `staging.paleon-lab-fintech.co.uk.s3-website-eu-west-1.amazonaws.com` — S3 website endpoints follow pattern `<bucket>.s3-website-<region>.amazonaws.com`. The embedded `paleon-lab-fintech.co.uk` makes this an invalid bucket name.

2. `paleon-lab-old-env.herokudns.com` — Heroku DNS targets are `<app-name>.herokudns.com`. This app name doesn't exist and the `paleon-lab-` prefix reserves the namespace.

---

## File Structure on EC2

```
/var/www/paleon-fintech/
├── main/                    # paleon-lab-fintech.co.uk
│   ├── index.html
│   ├── about/index.html
│   ├── services/index.html
│   ├── solutions/index.html
│   ├── resources/index.html
│   ├── contact/index.html
│   ├── .env                 # INTENTIONALLY EXPOSED
│   ├── css/main.css
│   ├── js/main.js
│   └── static/
│       ├── brand-mark.svg
│       ├── favicon.svg
│       └── hero-dashboard.svg
├── app/                     # app.paleon-lab-fintech.co.uk
│   └── index.html
├── api/                     # api.paleon-lab-fintech.co.uk
│   ├── index.html
│   └── swagger.json         # FAKE OpenAPI 3.1
└── dev/                     # dev.paleon-lab-fintech.co.uk
    └── index.html
```

---

## Deployment Checklist

### Pre-Deployment
- [ ] Domain registered: `paleon-lab-fintech.co.uk`
- [ ] AWS account access confirmed
- [ ] Region: eu-west-2
- [ ] Admin IP identified for SSH

### Infrastructure (Terraform)
- [ ] Launch t4g.nano Ubuntu 26.04 LTS ARM64
- [ ] Allocate/associate Elastic IP
- [ ] Configure security group (80, 443, 5432, SSH from admin IP)
- [ ] Verify SSH access

### DNS
- [ ] A records for all 5 hosts
- [ ] CNAME records for staging & dev-old (takeover indicators)
- [ ] SPF TXT record (weak ~all)
- [ ] DMARC TXT record (p=none)
- [ ] DNSSEC disabled confirmed
- [ ] Propagation verified

### Server Setup
- [ ] Ubuntu updated
- [ ] Nginx + headers-more module installed
- [ ] socat installed
- [ ] Self-signed cert generated (valid, 10 years)
- [ ] Website files deployed to /var/www/paleon-fintech/
- [ ] Nginx config deployed (4 vhosts)
- [ ] Dummy postgres service created & started
- [ ] Nginx tested & reloaded

### Verification
- [ ] All 4 HTTPS hosts load
- [ ] Clean URLs work (/about, /services, etc.)
- [ ] /.env accessible with fake values
- [ ] /swagger.json valid OpenAPI 3.1
- [ ] App host: no HSTS header
- [ ] Dev host: Server: nginx/1.14.0, TLS 1.0/1.1 enabled
- [ ] Port 5432 reachable (TCP accept/close)
- [ ] Port 22 restricted to admin IP
- [ ] Ports 3306, 3389, 445, 23, 25, 6379, 27017 NOT reachable
- [ ] DNS records correct (SPF, DMARC, CNAMEs)

---

## Cost Estimate (eu-west-2, monthly)

| Component | Cost |
|-----------|------|
| t4g.nano instance | ~$3.00 |
| Elastic IP (attached) | $0.00 |
| 8 GB gp3 storage | ~$0.80 |
| Data transfer (minimal) | ~$1-2.00 |
| **Total** | **~$5-6/month** |

One-time: Domain registration ~£10-15/year

---

## Security Boundaries

### Contains (Intentional Test Conditions)
- Fake company website with synthetic data
- Dummy TCP listener on port 5432
- Self-signed TLS certificate (valid)
- Intentionally missing HSTS on 2 hosts
- Outdated Server header on dev host
- Legacy TLS protocols on dev host
- Exposed fake .env file
- Exposed fake OpenAPI spec
- Safe subdomain-takeover indicators

### Does NOT Contain
- Real customer data or PII
- Real credentials, keys, tokens
- Real PostgreSQL/MySQL/Redis/MongoDB
- Real RDP/SMB/Telnet/SMTP services
- Real subdomain takeover targets
- Production secrets
- Access to Paleon production infrastructure

### Isolation
- Dedicated AWS account or isolated VPC recommended
- No IAM roles with production permissions
- No VPC peering to production
- All data synthetic

---

## Comparison: Site 1 vs Site 4

| Aspect | Site 1 (Fintech) | Site 4 (Northbridge) |
|--------|------------------|---------------------|
| TLS Certificate | Valid self-signed | **Expired** self-signed |
| Port 5432 | Dummy listener | N/A |
| Port 3389 | NOT exposed | Dummy listener |
| HSTS missing | app + dev hosts | main + old subdomain |
| CSP missing | None | main + old subdomain |
| Outdated Server | dev host only | main + old subdomain |
| Exposed file | /.env (fake) | /backup.bak (fake) |
| API spec | /swagger.json (fake) | N/A |
| Subdomain takeover | 2 safe CNAMEs | old.paleon-lab-sme.co.uk (real old site) |
| DMARC | p=none | p=none |
| SPF | weak (~all) | weak (~all) |
| DNSSEC | disabled | disabled |
| Instance | t4g.nano ARM64 | t4g.nano ARM64 |

---

## Maintenance

### Regular Tasks
- Ubuntu security updates: Monthly
- Service health check: Weekly
- Certificate validity: Quarterly (ensure NOT expired)
- Scanner re-test: On demand

### Reset Procedure
```bash
sudo systemctl stop nginx dummy-postgres
sudo rm -rf /var/www/paleon-fintech/*
# Redeploy from git
cd /tmp && git clone [repo-url]
sudo cp -r fintech/* /var/www/paleon-fintech/
sudo systemctl start nginx dummy-postgres
# Verify
curl -Ik https://paleon-lab-fintech.co.uk
nc -zv paleon-lab-fintech.co.uk 5432
```

---

**Architecture Status:** ✅ Defined  
**Deployment Status:** ⏳ Awaiting Terraform implementation  
**Estimated Setup Time:** 2-3 hours  
**Monthly Cost:** ~$5-6