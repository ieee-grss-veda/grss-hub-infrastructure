# ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
resource "aws_ecr_repository" "pilot_hub" {
  name                 = "pilot-hub"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    "2i2c:hub-name" = "shared"   # cost allocation: shared image, not per-hub
  }
}

# Keep the last 20 images to avoid runaway storage cost
resource "aws_ecr_lifecycle_policy" "pilot_hub" {
  repository = aws_ecr_repository.pilot_hub.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "pilot_hub_ecr_repository_url" {
  value       = aws_ecr_repository.pilot_hub.repository_url
  description = "ECR repository URL the operator points chartpress.yaml at"
}