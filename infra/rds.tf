# RDS still needs to know WHICH subnets it can live in, even though we're
# not using private subnets. "Public subnet" and "publicly accessible" are
# two different things (see publicly_accessible below) — this is that
# distinction made concrete.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro" # free-tier eligible, plenty for learning

  allocated_storage = 20
  storage_type       = "gp3"

  db_name  = "appdb"
  username = "appuser"
  password = random_password.rds_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # This is the actual isolation control — NOT the subnet's "public" CIDR.
  # Even sitting in a public subnet, RDS gets no public IP/endpoint here.
  publicly_accessible = false

  # Learning-project trade-offs, deliberately cost/simplicity-optimized:
  multi_az                = false # no standby replica — saves cost, no HA needed to learn the concepts
  backup_retention_period  = 0    # no automated backups — nothing here is real data
  skip_final_snapshot      = true # `terraform destroy` won't be blocked waiting on a snapshot

  tags = { Name = "${var.project_name}-db" }
}
