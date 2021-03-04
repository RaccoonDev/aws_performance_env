variable "aws_access_key" {
  type = string
}

variable "aws_secret_key" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "az_one" {
  type = string
}

variable "az_two" {
  type = string
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "devraccoon-terraform"
    key    = "test_env"
    region = "eu-central-1"
  }
}

resource "aws_vpc" "test-env" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "test-env"
  }
}

resource "aws_subnet" "subnet-uno" {
  cidr_block        = cidrsubnet(aws_vpc.test-env.cidr_block, 3, 1)
  vpc_id            = aws_vpc.test-env.id
  availability_zone = var.az_one
}

resource "aws_subnet" "subnet-duo" {
  cidr_block        = cidrsubnet(aws_vpc.test-env.cidr_block, 3, 2)
  vpc_id            = aws_vpc.test-env.id
  availability_zone = var.az_two
}

resource "aws_security_group" "ingress_ssh" {
  name   = "allow-ssh"
  vpc_id = aws_vpc.test-env.id

  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    ipv6_cidr_blocks = [
      "::/0"
    ]

    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "performance_test_1" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t2.micro"
  tags = {
    Name    = "Pefromance Test 1"
    Purpose = "PerformanceTesting"
  }
  key_name               = "MyDefaultKeyPair"
  vpc_security_group_ids = [aws_security_group.ingress_ssh.id]
  subnet_id              = aws_subnet.subnet-uno.id
  user_data              = file("configure_instance.sh")
}

resource "aws_instance" "performance_test_2" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t2.micro"
  tags = {
    Name    = "Pefromance Test 2"
    Purpose = "PerformanceTesting"
  }
  key_name               = "MyDefaultKeyPair"
  vpc_security_group_ids = [aws_security_group.ingress_ssh.id]
  subnet_id              = aws_subnet.subnet-uno.id
  user_data              = file("configure_instance.sh")
}

resource "aws_internet_gateway" "test-env-gw" {
  vpc_id = aws_vpc.test-env.id

  tags = {
    Name = "Test Env GW"
  }
}

resource "aws_route_table" "route-table-test-env" {
  vpc_id = aws_vpc.test-env.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test-env-gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.test-env-gw.id
  }

  tags = {
    Name = "test-env-route-table"
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.test-env.id
  route_table_id = aws_route_table.route-table-test-env.id
}

resource "aws_eip" "performance_test_1_ip" {
  instance = aws_instance.performance_test_1.id
  vpc      = true
}

output "performance_test_instance_1_ip" {
  value = aws_eip.performance_test_1_ip.public_ip
}

output "performance_test_instance_1_public_dns" {
  value = aws_eip.performance_test_1_ip.public_dns
}

output "performance_test_instance_2_internal_ip" {
  value = aws_instance.performance_test_2.private_ip
}

//////////////// RDS ////////////////

resource "aws_security_group" "db" {
  name = "db_security_group"

  description = "RDS postgres servers (terraform-managed)"
  vpc_id      = aws_vpc.test-env.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_db_subnet_group" "db_subnet_1" {
  name       = "main"
  subnet_ids = [aws_subnet.subnet-uno.id, aws_subnet.subnet-duo.id]

  tags = {
    Name = "Perf Test DB Subnet 1"
  }
}

resource "aws_db_instance" "perf_db_1" {
  allocated_storage       = 20
  backup_retention_period = 1
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_1.name
  engine                  = "postgres"
  engine_version          = "12.5"
  identifier              = "perfdb1"
  instance_class          = "db.t2.micro"
  multi_az                = false
  name                    = "perf_db_1"
  password                = var.db_password
  port                    = 5432
  publicly_accessible     = false
  storage_encrypted       = false
  storage_type            = "gp2"
  username                = "perf_db_user"
  vpc_security_group_ids  = [aws_security_group.db.id]
}
