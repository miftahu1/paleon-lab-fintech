# Paleon Fintech Test Site (Site 1)

**Domain:** `paleon-lab-fintech.co.uk`  
**Purpose:** Non-intrusive external scanner test environment for Paleon  
**Status:** Test lab — NOT production

---

## Overview

This is a fictional UK fintech/payments SME website ("Tessera Financial") with **deliberately planted, externally-observable scanner test conditions**. It is designed to validate the Paleon external scanner's detection capabilities across multiple finding categories.

**This is a test environment. All data is synthetic. No real services, databases, or authentication exist.**

---

## Hosts (4 virtual hosts + 1 CNAME-only)

| Host | Purpose | Intentional Test Conditions |
|------|---------|----------------------------|
| `paleon-lab-fintech.co.uk` | Main marketing site | Exposes `/.env` with fake placeholders; fake AWS ARN reference |
| `app.paleon-lab-fintech.co.uk` | App console (static mock) | **HSTS header OMITTED**; no authentication |
| `api.paleon-lab-fintech.co.uk` | API reference | Exposes `/swagger.json` (fake OpenAPI 3.1 spec) |
| `dev.paleon-lab-fintech.co.uk` | Legacy dev portal | **Outdated Server header** (`nginx/1.14.0`); legacy TLS 1.0/1.1; no HSTS |
| `staging.paleon-lab-fintech.co.uk` | CNAME only | **Safe subdomain-takeover indicator** (dangling CNAME to non-existent target) |

---

## Network / Infrastructure Test Conditions

| Condition | Details |
|-----------|---------|
| **TCP 5432 reachable** | Dummy TCP listener (socat) accepts connections on PostgreSQL port. **No real PostgreSQL.** |
| **TCP 22 restricted** | SSH only from administrator IP |
| **Ports NOT exposed** | 3306, 3389, 445, 23, 25, 6379, 27017 |
| **DMARC** | `p=none` (monitoring only) |
| **SPF** | Weak (`~all`) |
| **DNSSEC** | Disabled (intentional) |
| **TLS Certificate** | Self-signed, **NOT expired** (Site 4 uses expired cert) |

---

## Expected Scanner Findings

See [`expected.yaml`](expected.yaml) for the complete, machine-readable list of what the Paleon scanner **should** and **must not** detect.

The findings are organized into three categories:

### Category 1: Scanner Detections (13 findings — Intentional Issues)
These are actual security issues intentionally planted for the scanner to detect:
- `.env` file exposure at main site (fake placeholders only)
- HSTS **missing** on app host
- No authentication on app host
- `/swagger.json` exposed on API host (fake OpenAPI 3.1)
- Outdated `Server: nginx/1.14.0` header on dev host
- Legacy TLS (1.0/1.1) enabled on dev host
- HSTS **missing** on dev host
- Two safe subdomain-takeover indicators (dangling CNAMEs)
- Port 5432 reachable (dummy listener, no PostgreSQL)
- DMARC `p=none` (monitoring only)
- SPF weak (`~all` softfail)
- DNSSEC disabled
- (Fake AWS ARN in `.env` — must NOT flag as real secret)

### Category 2: Positive Observations (8 findings — Security Controls Working)
These represent GOOD security posture that the scanner should verify:
- HSTS present on main site
- Content-Security-Policy present on main site
- Clean URL routing (no .html extensions)
- HSTS present on API host
- SSH (port 22) restricted to admin IP
- Risky ports NOT exposed (3306, 3389, 445, 23, 25, 6379, 27017)
- TLS certificate valid (not expired)
- OpenAPI spec contains only synthetic/fake examples

### Category 3: False-Positive Guardrails (8 patterns — Must NOT Flag)
These patterns must NOT be reported as real findings:
- Real AWS credentials (fake ARN uses `example` partition)
- Real Stripe keys (fake `pk_test_fakeplaceholder...`)
- Real Sentry DSN (fake `@sentry.example.com`)
- PostgreSQL service on port 5432 (dummy listener only)
- Exploitable subdomain takeover (targets don't exist, can't be claimed)
- Confirmed CVE for nginx 1.14.0 (indicator only)
- Expired TLS cert (this site's cert is valid)
- Real customer data (all synthetic)

**Total: 29 validation test cases (13 scanner detections + 8 positive observations + 8 false-positive guardrails)**

---

## File Structure

```
fintech/
├── index.html                    # Main site homepage
├── .env                          # INTENTIONALLY EXPOSED (fake values only)
├── expected.yaml                 # Ground truth for scanner validation (REQUIRED)
├── nginx.conf                    # All 4 virtual hosts + test conditions
├── subdomain-takeover-indicator.txt  # Documents safe CNAME indicators
├── dummy-postgres.listener.service   # systemd service for port 5432
├── deploy.sh                     # Deployment script
├── reset.sh                      # Reset to clean state
├── validate.sh                   # Local validation checks
├── ARCHITECTURE.md               # Architecture decisions
├── DEPLOYMENT.md                 # Step-by-step deployment guide
├── .gitignore                    # Excludes secrets, keys, terraform state
├── css/
│   └── main.css                  # Design system (tokens, components, dev-mode overrides)
├── js/
│   └── main.js                   # Mobile nav, year stamp, form validation (no backend)
├── static/
│   ├── brand-mark.svg            # Logo mark
│   ├── favicon.svg               # Favicon
│   └── hero-dashboard.svg        # Hero illustration
├── about/index.html              # About page
├── services/index.html           # Services & pricing
├── solutions/index.html          # Solutions by use case
├── resources/index.html          # Docs, legal, status
├── contact/index.html            # Contact form (local validation only)
├── app/
│   └── index.html                # App console mock (no auth, no backend)
├── api/
│   ├── index.html                # API landing page
│   └── swagger.json              # Fake OpenAPI 3.1 spec
├── dev/
│   └── index.html                # Legacy dev portal (outdated component indicators)
└── terraform/
    ├── main.tf                   # AWS resources
    ├── variables.tf              # Input variables
    ├── outputs.tf                # Outputs
    └── README.md                 # Terraform usage
```

---

## Design Identity

**Distinct from Site 4 (Northbridge).** This site uses:

- **Editorial/ledger aesthetic** — paper texture, brass accents, structured tables
- **Typography:** Fraunces (serif display), IBM Plex Sans (UI), IBM Plex Mono (technical)
- **Color palette:** Paper `#f6f3ec`, Ink `#191b20`, Forest `#1f4d3c`, Brass `#a8743a`
- **No generic SaaS/crypto look** — no dark-mode-first, no neon gradients, no "trust badges"

---

## Deployment

**Target:** AWS EC2 `t4g.nano` (ARM64), Ubuntu 26.04 LTS, `eu-west-2` (London)  
**IaC:** Terraform (in `terraform/`)  
**Web server:** Nginx with the Ubuntu `libnginx-mod-http-headers-more-filter` package; the packaged config in `/etc/nginx/modules-enabled/` loads the module automatically.  
**Port 5432:** Separate `socat` dummy TCP listener (systemd service); no PostgreSQL service is implemented.

### Quick Start

```bash
# 1. Review and customize terraform/variables.tf
# 2. Deploy infrastructure
cd terraform
terraform init
terraform plan
terraform apply

# 3. Configure DNS at your registrar (A records + TXT for SPF/DMARC)
# 4. Deploy website files to EC2 (see deploy.sh)
# 5. Validate (see validate.sh)
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete steps.

---

## Security Boundaries

| Contains | Does NOT Contain |
|----------|------------------|
| Test website with fake company data | Real customer data |
| Dummy TCP listener on port 5432 | Real PostgreSQL/MySQL/Redis/MongoDB |
| Self-signed TLS certificate | Real CA-issued certificate |
| Intentionally misconfigured headers | Production secrets |
| Exposed fake `.env` file | Real credentials/keys/tokens |
| Safe subdomain-takeover indicators | Actually claimable targets |
| Fake OpenAPI spec | Real API backend |

**Isolation:** Deploy in dedicated AWS account or isolated VPC. No access to Paleon production infrastructure.

---

## Validation

After deployment, run local checks:

```bash
./validate.sh
```

This verifies:
- All routes return 200
- `.env` accessible with fake values
- `swagger.json` valid JSON, correct structure
- Security headers present/absent as expected
- Port 5432 reachable (TCP only)
- DNS records correct

**Final validation** is performed by the Paleon external scanner against `expected.yaml`.

---

## Maintenance

| Task | Frequency |
|------|-----------|
| Security updates (Ubuntu) | Monthly |
| Certificate check | Quarterly |
| Service health | Weekly |
| Scanner re-test | On demand |

### Reset to Clean State

```bash
./reset.sh
```

Stops services, clears web roots, redeploys from git, restarts services.

---

## Related Sites

- **Site 4 (Northbridge):** `paleon-lab-sme.co.uk` — expired TLS, port 3389, backup.bak exposure
- **Site 2, 3, 5+:** Future test sites

---

## License & Attribution

Fictional test environment for Paleon scanner validation.  
All company names, data, credentials, and certificates are synthetic.  
Do not use for real traffic or real data.

---

**Generated:** 2026-08-30  
**Paleon Test Lab — Site 1 Build**