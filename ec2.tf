data "aws_ami" "my_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "aws_iam_instance_profile" "my_ssm_profile" {
  name = "EC-SSM-Role"
}

data "aws_ssm_parameter" "token" {
  name = "/devops-bootcamp-2026/tunnel-token"
}

module "web_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name                        = "web-server"
  ami                         = data.aws_ami.my_ami.id
  instance_type               = "t3.micro"
  subnet_id                   = module.my_vpc.public_subnets[0]
  private_ip                  = "10.0.0.5"
  create_security_group       = false
  vpc_security_group_ids      = [module.my_sg.id]
  iam_instance_profile        = data.aws_iam_instance_profile.my_ssm_profile.name
  key_name                    = "abdhakim-keypair"
  user_data                   = file("target-userdata.sh")
  tags                        = { Name = "web-server" }
  user_data_replace_on_change = true


}

module "ansible_controller" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name                        = "ansible_controller"
  ami                         = data.aws_ami.my_ami.id
  instance_type               = "t3.micro"
  subnet_id                   = module.my_vpc.private_subnets[0]
  private_ip                  = "10.0.0.135"
  iam_instance_profile        = data.aws_iam_instance_profile.my_ssm_profile.name
  vpc_security_group_ids      = [module.my_sg.id]
  create_security_group       = false
  key_name                    = "abdhakim-keypair"
  user_data                   = file("controller-userdata.sh")
  tags                        = { Name = "ansible_controller" }
  user_data_replace_on_change = true


}

module "monitoring_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name                        = "monitoring_server"
  ami                         = data.aws_ami.my_ami.id
  instance_type               = "t3.micro"
  subnet_id                   = module.my_vpc.private_subnets[0]
  private_ip                  = "10.0.0.136"
  iam_instance_profile        = data.aws_iam_instance_profile.my_ssm_profile.name
  create_security_group       = false
  vpc_security_group_ids      = [module.my_sg.id]
  key_name                    = "abdhakim-keypair"
  user_data                   = file("target-userdata.sh")
  tags                        = { Name = "monitoring-server" }
  user_data_replace_on_change = true
  root_block_device = {
      volume_size = 20
      volume_type = "gp3"
    }
  
}
