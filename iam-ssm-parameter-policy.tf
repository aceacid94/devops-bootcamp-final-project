# Attach Parameter Store permissions to your existing EC2-SSM-Role,
# since AmazonSSMManagedInstanceCore alone does not include ssm:PutParameter
# or ssm:GetParameter for custom parameters.

data "aws_iam_role" "ec2_ssm_role" {
  name = "EC-SSM-Role" # must match the exact IAM role name shown in your EC2 console
}

resource "aws_iam_role_policy" "ssm_parameter_access" {
  name = "ssm-parameter-handoff"
  role = data.aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/devops-bootcamp/*"
      }
    ]
  })
}
