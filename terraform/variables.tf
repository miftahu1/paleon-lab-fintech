# =============================================================================
# Paleon Fintech Test Site (Site 1) — Terraform Variables
# Copy to terraform.tfvars and fill in your values.
# =============================================================================

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-2"
}

variable "domain_name" {
  description = "Primary domain name (must be registered)"
  type        = string
  default     = "paleon-lab-fintech.co.uk"
}

variable "admin_ip" {
  description = "Administrator IP CIDR for SSH access (e.g., '203.0.113.45/32')"
  type        = string
  # No default - MUST be set in terraform.tfvars
}

variable "public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "instance_type" {
  description = "EC2 instance type (ARM64)"
  type        = string
  default     = "t4g.nano"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "use_route53" {
  description = "Whether to create Route53 records (requires hosted zone)"
  type        = bool
  default     = false
}