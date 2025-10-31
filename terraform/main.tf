# ======== PROVIDER ========
provider "aws" {
  region = var.aws_region
}

# ======== KEY PAIR ========
resource "aws_key_pair" "terraform_key" {
  key_name   = "terraform-key"
  public_key = file("terraform-key.pem.pub")
}

# ======== SECURITY GROUP ========
resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  description = "Allow SSH and HTTP access"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ======== UBUNTU AMI ========
data "aws_ami" "ubuntu_jammy" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ======== EC2 INSTANCE ========
resource "aws_instance" "nginx_server" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.terraform_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive

    echo "===== UPDATE SYSTEM AND INSTALL NGINX ====="
    apt-get update -y
    apt-get install -y nginx curl jq

    echo "===== CONFIGURE NGINX ROOT TO /var/www/html ====="
    sed -i 's|root /usr/share/nginx/html;|root /var/www/html;|' /etc/nginx/sites-enabled/default
    systemctl enable nginx
    systemctl start nginx

    echo "<h1>Hello from Terraform NGINX + Self-Hosted Runner!</h1>" > /var/www/html/index.html
    chown www-data:www-data /var/www/html/index.html

    echo "===== INSTALL GITHUB RUNNER ====="
    RUNNER_VER="2.316.1"
    RUNNER_TGZ="actions-runner-linux-x64-$${RUNNER_VER}.tar.gz"

    mkdir -p /home/ubuntu/actions-runner
    cd /home/ubuntu/actions-runner
    curl -sSL -o $${RUNNER_TGZ} "https://github.com/actions/runner/releases/download/v$${RUNNER_VER}/$${RUNNER_TGZ}"
    tar xzf $${RUNNER_TGZ}
    chown -R ubuntu:ubuntu /home/ubuntu/actions-runner

    echo "===== CONFIGURE RUNNER ====="
    sudo -u ubuntu bash -c "./config.sh --unattended --url ${var.github_repo_url} --token ${var.runner_token} --name ${var.runner_name} --labels self-hosted,ubuntu,x64 --work _work"

    echo "===== CREATE SYSTEMD SERVICE ====="
    cat > /etc/systemd/system/actions-runner.service <<SERVICE
    [Unit]
    Description=GitHub Actions Runner
    After=network.target

    [Service]
    ExecStart=/home/ubuntu/actions-runner/run.sh
    User=ubuntu
    WorkingDirectory=/home/ubuntu/actions-runner
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now actions-runner.service

    echo "===== SETUP COMPLETE ====="
  EOF

  tags = {
    Name = "nginx-terraform-server"
  }
}

# ======== OUTPUTS ========
output "instance_public_ip" {
  value       = aws_instance.nginx_server.public_ip
  description = "Public IP of the EC2 instance"
}

output "instance_url" {
  value       = "http://${aws_instance.nginx_server.public_ip}"
  description = "Direct HTTP URL of the deployed NGINX site"
}

