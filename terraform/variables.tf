variable "aws_region" {
  description = "AWS region"
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "github_repo_url" {
  description = "GitHub repository URL"
}

variable "runner_token" {
  description = "GitHub Actions runner token"
}

variable "runner_name" {
  description = "GitHub Actions runner name"
}

