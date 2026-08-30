# Terraform — Paleon Fintech Test Site (Site 1)

This directory contains Infrastructure-as-Code for Site 1 (Fintech test site).

## What It Provisions

| Resource | Purpose |
|----------|---------|
| VPC | Isolated network |
| Internet Gateway | Internet access |
| Public Subnet | EC2 in public subnet (with EIP) |
| Route Table | 0.0.0.0/0 → IGW |
| Security Group | 80, 443, 5432 public; 22 admin-only |
| SSH Key Pair | Deploy key (public key uploaded) |
| EC2 t4g.nano | Ubuntu 26.04 ARM64, user-data installs nginx + socat |
| Elastic IP | Static IP for DNS |
| Route53 (optional) | DNS records if `use_route53 = true` |

## Important Notes

### What Terraform Does NOT Do

- **Does not deploy website files** — use `deploy.sh` after `apply`
- **Does not generate TLS certificate** — done post-apply (keeps private key off Terraform state)
- **Does not configure nginx virtual hosts** — `deploy.sh` copies `nginx.conf`
- **Does not start the dummy postgres listener** — `deploy.sh` installs the systemd service

Rationale: Keep secrets (TLS private key, SSH private key) out of Terraform state.

### Security Group

```
Inbound:
  80/tcp   0.0.0.0/0     HTTP (redirect)
  443/tcp  0.0.0.0/0     HTTPS
  5432/tcp 0.0.0.0/0     Dummy TCP listener (INTENTIONAL; no PostgreSQL)
  22/tcp   <admin_ip>    SSH (restricted)
Outbound:
  all      0.0.0.0/0
```

Forbidden ports (NOT exposed): 3306, 3389, 445, 23, 25, 6379, 27017

## Usage

### 1. Create terraform.tfvars

```hcl
admin_ip       = "203.0.113.45/32"   # YOUR IP
public_key_path = "/path/to/your-public-key.pub"  # *.pub, not a private *.pem
domain_name    = "paleon-lab-fintech.co.uk"
use_route53    = false               # true if using Route53 hosted zone
```

Use the matching private key for SSH access, for example:
`ssh -i /path/to/your-private-key.pem ubuntu@<public-ip>`

### 2. Initialize & Plan

```bash
terraform init
terraform plan -out=tfplan
```

### 3. Apply

```bash
terraform apply tfplan
```

### 4. Capture Outputs

```bash
terraform output elastic_ip
terraform output ssh_command
```

### 5. Post-Apply Steps

See `DEPLOYMENT.md` Steps 2-8:
- Configure DNS (or rely on Route53 records)
- Generate self-signed TLS cert
- Run `../deploy.sh ubuntu@<elastic_ip>`
- Verify with `../validate.sh`

## Variables

See `variables.tf` for full list. Key inputs:

| Variable | Default | Notes |
|----------|---------|-------|
| `region` | eu-west-2 | London |
| `domain_name` | paleon-lab-fintech.co.uk | |
| `admin_ip` | (required) | SSH restriction |
| `instance_type` | t4g.nano | ARM64 smallest |
| `use_route53` | false | Set true for DNS automation |

## Teardown

```bash
terraform destroy
```

This removes all AWS resources. DNS records (if Route53) are also destroyed.

## Cost

~$5-6/month (t4g.nano + EIP + 8GB gp3).

## Security

- No IAM roles with production permissions
- SSH restricted to admin IP
- Isolated VPC
- All test data synthetic

---

**Paleon Test Lab — Site 1 Build**
