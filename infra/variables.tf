variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name, used in tags and resource naming"
  type        = string
  default     = "learning"
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names"
  type        = string
  default     = "devops-task"
}

variable "backend_image_tag" {
  description = "Git-sha tag of the backend image in ECR to deploy"
  type        = string
  default     = "initial" # placeholder until CI pushes a real tag; service will just sit unhealthy until then
}

variable "frontend_image_tag" {
  description = "Git-sha tag of the frontend image in ECR to deploy"
  type        = string
  default     = "initial"
}
