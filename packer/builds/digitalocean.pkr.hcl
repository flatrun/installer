packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.1.0"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

source "digitalocean" "flatrun" {
  api_token     = var.do_token
  image         = "ubuntu-22-04-x64"
  region        = "nyc3"
  size          = "s-1vcpu-1gb"
  ssh_username  = "root"
  snapshot_name = local.image_name
  snapshot_regions = [
    "nyc1", "nyc3", "sfo3", "ams3", "sgp1", "lon1", "fra1", "tor1", "blr1", "syd1"
  ]
  tags = ["flatrun", "marketplace"]
}

build {
  sources = ["source.digitalocean.flatrun"]

  provisioner "shell" {
    inline = ["cloud-init status --wait || true"]
  }

  provisioner "shell" {
    scripts = [
      "${path.root}/../scripts/00-base-setup.sh",
      "${path.root}/../scripts/01-install-docker.sh",
      "${path.root}/../scripts/02-install-flatrun.sh",
      "${path.root}/../scripts/04-configure-systemd.sh",
      "${path.root}/../scripts/99-cleanup.sh"
    ]
    environment_vars = [
      "FLATRUN_VERSION=${var.version}"
    ]
  }
}
