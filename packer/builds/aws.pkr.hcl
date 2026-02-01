packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = var.aws_region
}

source "amazon-ebs" "flatrun" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  region        = var.aws_region
  source_ami    = data.amazon-ami.ubuntu.id
  instance_type = "t3.micro"
  ssh_username  = "ubuntu"
  ami_name      = local.image_name
  ami_description = "FlatRun ${var.version} - Container Orchestration Platform"

  ami_regions = [
    "us-east-1",
    "us-west-2",
    "eu-west-1",
    "eu-central-1",
    "ap-southeast-1"
  ]

  tags = {
    Name        = local.image_name
    Application = "FlatRun"
    Version     = var.version
    OS          = "Ubuntu 22.04"
  }

  snapshot_tags = {
    Name        = local.image_name
    Application = "FlatRun"
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 25
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ena_support = true
}

build {
  sources = ["source.amazon-ebs.flatrun"]

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
    execute_command = "sudo -S env {{ .Vars }} bash '{{ .Path }}'"
  }
}
