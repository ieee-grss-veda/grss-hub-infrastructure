/*
 Some of the assumptions this jinja2 template makes about the cluster:
   - location of the nodes of the kubernetes cluster will be <region>a
   - no default scratch buckets support
*/
region                 = "us-west-2"
cluster_name           = "grss-veda"
cluster_nodes_location = "us-west-2a"

# Tip: uncomment and verify any missing info in the lines below if you want
#       to setup scratch buckets for the hubs on this cluster.
#

ebs_volumes = {
  "staging" = {
    name_suffix = "staging",
    type        = "gp3",
    size        = 2000,
    iops        = 6000,
    tags        = { "2i2c:hub-name" : "staging" },
  },
  "prod" = {
    name_suffix = "prod",
    type        = "gp3",
    size        = 2000,
    iops        = 6000,
    tags        = { "2i2c:hub-name" : "prod" },
  },

}

# EFS filestores for NFS home directories
filestores = {
  "staging" = {
    name_suffix = "staging",
    tags        = { "2i2c:hub-name" : "staging" },
  },
  "prod" = {
    name_suffix = "prod",
    tags        = { "2i2c:hub-name" : "prod" },
  },
}

enable_nfs_backup = true


# "scratch-staging" : {
#   "delete_after" : 7,
#   "tags" : { "2i2c:hub-name" : "staging" },
# },

# "scratch-prod" : {
#   "delete_after" : 7,
#   "tags" : { "2i2c:hub-name" : "prod" },
# },


# Cloud permissions for hub user pods (via IRSA).
# staging & prod: read/write to the existing external S3 bucket `hdcrs-school-2026`
#          and read/pull access to the `hdcrs-school-2026` ECR repository.
# Both resources are external (not created by this terraform), so access is
# granted via extra_iam_policy scoped to their exact ARNs.
hub_cloud_permissions = {
  "staging" : {
    extra_iam_policy : <<-EOT
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
              "arn:aws:s3:::hdcrs-school-2026",
              "arn:aws:s3:::hdcrs-school-2026/*"
            ]
          },
          {
            "Effect": "Allow",
            "Action": "s3:ListAllMyBuckets",
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "ecr:BatchGetImage",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchCheckLayerAvailability",
              "ecr:DescribeImages",
              "ecr:DescribeRepositories",
              "ecr:ListImages"
            ],
            "Resource": "arn:aws:ecr:us-west-2:870461445243:repository/hdcrs-school-2026"
          }
        ]
      }
    EOT
  },
  "prod" : {
    extra_iam_policy : <<-EOT
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
              "arn:aws:s3:::hdcrs-school-2026",
              "arn:aws:s3:::hdcrs-school-2026/*"
            ]
          },
          {
            "Effect": "Allow",
            "Action": "s3:ListAllMyBuckets",
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "ecr:BatchGetImage",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchCheckLayerAvailability",
              "ecr:DescribeImages",
              "ecr:DescribeRepositories",
              "ecr:ListImages"
            ],
            "Resource": "arn:aws:ecr:us-west-2:870461445243:repository/hdcrs-school-2026"
          }
        ]
      }
    EOT
  },
}


# Uncomment to enable cost monitoring
enable_jupyterhub_cost_monitoring = true