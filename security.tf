data "http" "myip" {
  url = "https://ifconfig.me/ip"
}

module "my_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name            = "finalproject-vpc"
  use_name_prefix = false
  vpc_id          = module.my_vpc.vpc_id

  ingress_rules = {

    ssh_internal = {
      cidr_ipv4   = module.my_vpc.vpc_cidr_block
      ip_protocol = "tcp"
      from_port   = 22
      to_port     = 22
    }


    http = {
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "tcp"
      from_port   = 80
      to_port     = 80
    }

    node_exporter = {
      cidr_ipv4   = "10.0.0.136/32"
      ip_protocol = "tcp"
      from_port   = 9100
      to_port     = 9100
    }

    prometheus = {
      cidr_ipv4   = module.my_vpc.vpc_cidr_block
      ip_protocol = "tcp"
      from_port   = 9090
      to_port     = 9090
    }

    grafana = {
      cidr_ipv4   = module.my_vpc.vpc_cidr_block
      ip_protocol = "tcp"
      from_port   = 3000
      to_port     = 3000
    }

  }

  egress_rules = {
    all = { cidr_ipv4 = "0.0.0.0/0", ip_protocol = "-1" }
  }

  tags = { Name = "finalproject-vpc-sg" }
}
