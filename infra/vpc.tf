# No NAT Gateway on purpose (see README "Крок 3" decisions) — everything
# lives in public subnets. RDS/ECS isolation from the internet comes from
# Security Groups (next file), not from network topology.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ALB requires subnets in at least 2 different AZs — hence 2 subnets here,
# not 1. count = 2 picks the first two AZs the data source returned.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block               = "10.0.${count.index + 1}.0/24"
  availability_zone        = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch  = true # Fargate tasks here get a public IP automatically

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

# The "door" between the VPC and the internet. Without this, nothing in
# the VPC — however public the subnet's CIDR looks — can reach outside.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route table: "any traffic not destined for the VPC itself goes to the
# Internet Gateway". This IS what makes a subnet "public" in AWS terms —
# not naming, but having a default route (0.0.0.0/0) pointing at an IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
