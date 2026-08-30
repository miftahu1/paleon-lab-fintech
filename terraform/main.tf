# =============================================================================
# Paleon Fintech Test Site (Site 1) — Terraform Infrastructure
# Provider: AWS
# Region: eu-west-2 (London)
# Instance: t4g.nano (ARM64), Ubuntu 26.04 LTS
#
# This provisions:
#   - VPC, subnet, IGW, route table
#   - EC2 t4g.nano instance
#   - Elastic IP
#   - Security Group (80, 443, 5432 public; 22 admin-only)
#   - SSH key (generated locally, public key uploaded)
#
# NOTE: User data installs nginx + headers-more + socat but does NOT deploy
#       website files (use deploy.sh after apply). Certificate generation is
#       also done post-apply (see DEPLOYMENT.md Step 4) to keep keys off Terraform state.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "paleon-test-lab"
      Site        = "site-1-fintech"
      Environment = "test"
      ManagedBy   = "terraform"
      Owner       = "paleon"
    }
  }
}

# --- Data sources ------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-*-26.04-arm64-server-*",
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# --- Networking --------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "paleon-fintech-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "paleon-fintech-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = {
    Name = "paleon-fintech-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "paleon-fintech-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ----------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "paleon-fintech-sg"
  description = "Paleon Fintech Test Site security group (Site 1)"
  vpc_id      = aws_vpc.main.id

  # HTTP → redirect to HTTPS
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (all 4 vhosts)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # INTENTIONAL: dummy TCP listener reachable from Internet
  # (socat listener, no real PostgreSQL service)
  ingress {
    description = "Dummy TCP listener on 5432 (intentional test condition)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH — RESTRICTED to admin IP only
  ingress {
    description = "SSH (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Outbound — all traffic (for apt, DNS)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paleon-fintech-sg"
  }
}

# --- SSH Key ----------------------------------------------------------------

resource "aws_key_pair" "deploy" {
  key_name   = "paleon-fintech-key"
  public_key = file(var.public_key_path)

  tags = {
    Name = "paleon-fintech-key"
  }
}

# --- EC2 Instance ------------------------------------------------------------

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deploy.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true

  # Enforce IMDSv2 (required for security)
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      nginx \
      libnginx-mod-http-headers-more-filter \
      socat \
      openssl \
      git

    # AWS Security Group is the primary network boundary for this lab.
    # Do not create redundant host-level UFW rules that contradict the intended exposure.
    mkdir -p /var/www/paleon-fintech/{main,app,api,dev}

    systemctl enable nginx
    systemctl start nginx

    echo "Paleon Fintech Site 1 base provisioning complete" > /var/log/paleon-provision.log
  EOF

  tags = {
    Name = "paleon-fintech-web"
  }
}

# --- Elastic IP --------------------------------------------------------------

resource "aws_eip" "web" {
  domain                    = "vpc"
  network_interface         = aws_instance.web.primary_network_interface_id
  associate_with_private_ip = aws_instance.web.private_ip

  tags = {
    Name = "paleon-fintech-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# --- Route53 (optional, if using Route53) -----------------------------------

resource "aws_route53_zone" "main" {
  count = var.use_route53 ? 1 : 0
  name  = var.domain_name

  tags = {
    Name = "paleon-fintech-zone"
  }
}

resource "aws_route53_record" "main" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

resource "aws_route53_record" "www" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "www.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

resource "aws_route53_record" "app" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "app.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

resource "aws_route53_record" "api" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "api.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

resource "aws_route53_record" "dev" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "dev.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

# Subdomain-takeover safe indicators (CNAME to non-existent targets)
resource "aws_route53_record" "staging_cname" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "staging.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["staging.${var.domain_name}.s3-website-eu-west-1.amazonaws.com"]
}

resource "aws_route53_record" "devold_cname" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "dev-old.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["paleon-lab-old-env.herokudns.com"]
}

# SPF (weak - intentional)
resource "aws_route53_record" "spf" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:_spf.google.com ~all"]
}

# DMARC (p=none - intentional)
resource "aws_route53_record" "dmarc" {
  count   = var.use_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=none; rua=mailto:dmarc@${var.domain_name}"]
}
