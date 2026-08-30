# =============================================================================
# Paleon Fintech Test Site (Site 1) — Terraform Outputs
# =============================================================================

output "elastic_ip" {
  description = "Elastic IP address of the web instance"
  value       = aws_eip.web.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "instance_public_dns" {
  description = "Public DNS name of instance"
  value       = aws_instance.web.public_dns
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ${var.public_key_path} ubuntu@${aws_eip.web.public_ip}"
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.web.id
}

output "domain_name" {
  description = "Primary domain"
  value       = var.domain_name
}

output "next_steps" {
  description = "Post-apply checklist"
  value       = <<-EOT
    1. Configure DNS (if not using Route53):
       A records → ${aws_eip.web.public_ip} for: ${var.domain_name}, www, app, api, dev
       CNAME staging → staging.${var.domain_name}.s3-website-eu-west-1.amazonaws.com
       CNAME dev-old → paleon-lab-old-env.herokudns.com
       TXT SPF → v=spf1 include:_spf.google.com ~all
       TXT DMARC → v=DMARC1; p=none; rua=mailto:dmarc@${var.domain_name}
    2. SSH: ssh -i ${var.public_key_path} ubuntu@${aws_eip.web.public_ip}
    3. Generate TLS cert (see DEPLOYMENT.md Step 4)
    4. Deploy files: ./deploy.sh ubuntu@${aws_eip.web.public_ip}
    5. Run Paleon scanner → compare with expected.yaml
  EOT
}