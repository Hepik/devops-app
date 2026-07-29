terraform {
  backend "s3" {
    bucket = "devops-task-tf-state-1f37a6d4"
    key    = "devops-task/main.tfstate"
    region = "eu-central-1"

    dynamodb_table = "devops-task-tf-lock"
    encrypt        = true
  }
}
