terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Deliberately NO backend block here — this state stays local.
  # This bootstrap creates the S3 bucket/DynamoDB table that the MAIN
  # infra/ project will use as its remote backend.
}

provider "aws" {
  region = "eu-central-1"
}

# Bucket names must be globally unique across ALL of AWS, not just your
# account — a random suffix avoids picking an already-taken name.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
  
resource "aws_s3_bucket" "tf_state" {
  bucket = "devops-task-tf-state-${random_id.bucket_suffix.hex}"
}

# Versioning lets you recover a previous state file if something corrupts
# the current one (e.g. a bad apply, or manual edit gone wrong).
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# The state file contains secrets in plaintext (DB passwords, etc) by
# default — this is the mitigation the task instructions call out.
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking: prevents two `terraform apply` runs
# from racing each other and corrupting the state.
resource "aws_dynamodb_table" "tf_lock" {
  name         = "devops-task-tf-lock"
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for a lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
