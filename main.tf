# Environment Variables Handler
data "external" "env" {
  program = ["jq", "-n", "env"]
}

# Providers
provider "digitalocean" {
  token = data.external.env.result.DO_API_TOKEN
}

provider "aws" {
  region     = "eu-west-1"
  access_key = data.external.env.result.AWS_ACCESS_KEY
  secret_key = data.external.env.result.AWS_SECRET_KEY
}

# Variables
locals {
  name        = "es1305"
  hosts       = ["www-1"]
  image       = "ubuntu-20-04-x64"
  size        = "s-1vcpu-1gb"
  tags        = ["devops", "es1305_at_mail_ru"]
  region      = "ams3"
  dns_zone    = "devops.rebrain.srwx.net."
  remote_user = "root"
  public_key  = file("~/.ssh/id_rsa.pub")
}

# Execute
data "digitalocean_ssh_key" "rebrain" {
  name = "REBRAIN.SSH.PUB.KEY"
}

resource "digitalocean_ssh_key" "default" {
  name       = local.name
  public_key = local.public_key
}

resource "digitalocean_droplet" "web" {
  count    = length(local.hosts)
  name     = "${local.name}-${local.hosts[count.index]}"
  image    = local.image
  region   = local.region
  size     = local.size
  tags     = local.tags
  ssh_keys = [data.digitalocean_ssh_key.rebrain.id, digitalocean_ssh_key.default.fingerprint]
}

data "aws_route53_zone" "selected" {
  name         = local.dns_zone
  private_zone = false
}

resource "aws_route53_record" "new_record" {
  allow_overwrite = true
  count           = length(local.hosts)
  zone_id         = data.aws_route53_zone.selected.zone_id
  name            = "${local.name}-${local.hosts[count.index]}.${data.aws_route53_zone.selected.name}"
  type            = "A"
  ttl             = "300"
  records         = [digitalocean_droplet.web[count.index].ipv4_address]
}

# Ansible Inventory
resource "local_file" "AnsibleInventory" {
  content = templatefile("inventory.tmpl",
    {
      vm-ip   = digitalocean_droplet.web[*].ipv4_address
      vm-host = aws_route53_record.new_record[*].fqdn
      vm-user = local.remote_user
    }
  )
  filename             = "inventory.yml"
  directory_permission = "0755"
  file_permission      = "0600"
}

# Ansible Run
resource "null_resource" "AnsiblePlaybook" {
  depends_on = [local_file.AnsibleInventory]

  provisioner "local-exec" {
    command     = "ansible-playbook -i inventory.yml playbook.yml"
    interpreter = ["bash", "-c"]
  }
}

# Output
output "public_ip4" {
  value = [digitalocean_droplet.web[*].ipv4_address]
}

output "domain_name" {
  value = [aws_route53_record.new_record[*].fqdn]
}
