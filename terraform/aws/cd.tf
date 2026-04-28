/*
  Resources required for continuously deploying hubs to this cluster
*/

resource "aws_iam_user" "continuous_deployer" {
  name = "hub-continuous-deployer"
}

resource "aws_iam_access_key" "continuous_deployer" {
  user = aws_iam_user.continuous_deployer.name
}

resource "aws_iam_user_policy" "continuous_deployer" {
  name = "eks-and-kms-access"
  user = aws_iam_user.continuous_deployer.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "${data.aws_eks_cluster.cluster.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:${var.region}:*:key/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::grss-veda-tf-state-hub/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::grss-veda-tf-state-hub"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:${var.region}:*:table/terraform-locks"
    }
  ]
}
EOF
}


locals {
  cd_creds = {
    "AccessKey" = {
      "UserName" : aws_iam_user.continuous_deployer.name,
      "AccessKeyId" : aws_iam_access_key.continuous_deployer.id,
      "SecretAccessKey" : aws_iam_access_key.continuous_deployer.secret
    }
  }
}

output "continuous_deployer_creds" {
  value     = jsonencode(local.cd_creds)
  sensitive = true
}

output "eksctl_iam_command" {
  description = "eksctl command to grant cluster access to our CD"
  value       = <<-EOT
   eksctl create iamidentitymapping \
      --cluster ${var.cluster_name} \
      --region ${var.region} \
      --arn ${aws_iam_user.continuous_deployer.arn} \
      --username ${aws_iam_user.continuous_deployer.name}  \
      --group system:masters
  EOT
}
