# Create a VPC
resource "aws_vpc" "backstage_vpc" {
  cidr_block = "10.0.0.0/24"

  enable_dns_hostnames = true
  tags = local.tags
}

data "aws_availability_zone" "zoneA" {
  name = "eu-west-1a"
}

data "aws_availability_zone" "zoneB" {
  name = "eu-west-1b"
}

resource "aws_internet_gateway" "backstage_vpc_igw" {
  vpc_id = aws_vpc.backstage_vpc.id

  tags = local.tags
}

data "aws_route_table" "backstage_vpc_route_table" {
  vpc_id = aws_vpc.backstage_vpc.id
}

resource "aws_lb_target_group" "backstage_vpc_alb_target_group" {
  name     = "backstage-vpc-alb-target-group"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.backstage_vpc.id

  tags = local.tags
}


resource "aws_alb" "backstage_alb" {
  name    = "backstagealb"
  subnets = [aws_subnet.backstage_subnet_a.id, aws_subnet.backstage_subnet_b.id]
  security_groups = [aws_security_group.backstage_security_group.id]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_alb.backstage_alb.arn
  port              = "80"
  protocol          = "HTTP"

  # default_action {
  #   type = "fixed-response"

  #   fixed_response {
  #     content_type = "text/plain"
  #     message_body = "Fixed response content"
  #     status_code  = "200"
  #   }
  # }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backstage_vpc_alb_target_group.arn
  }

  tags = local.tags
}


resource "aws_route" "backstage_vpc_route" {
  gateway_id = aws_internet_gateway.backstage_vpc_igw.id
  route_table_id = data.aws_route_table.backstage_vpc_route_table.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_subnet" "backstage_subnet_a" {
  vpc_id     = aws_vpc.backstage_vpc.id
  cidr_block = "10.0.0.128/25"
  availability_zone_id = data.aws_availability_zone.zoneA.zone_id
  map_public_ip_on_launch = true

  tags = local.tags
}

resource "aws_subnet" "backstage_subnet_b" {
  vpc_id     = aws_vpc.backstage_vpc.id
  cidr_block = "10.0.0.0/25"
  availability_zone_id = data.aws_availability_zone.zoneB.zone_id
  map_public_ip_on_launch = true

  tags = local.tags
}

resource "aws_security_group" "backstage_security_group" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.backstage_vpc.id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "backstage_security_group_rule_egress2" {
  security_group_id = aws_security_group.backstage_security_group.id
  cidr_ipv4         = aws_vpc.backstage_vpc.cidr_block
  ip_protocol       = -1

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "backstage_security_group_rule_egress" {
  security_group_id = aws_security_group.backstage_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "backstage_security_group_rule_ingress2" {
  security_group_id = aws_security_group.backstage_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "backstage_security_group_rule_ingress" {
  security_group_id = aws_security_group.backstage_security_group.id
  cidr_ipv4         = aws_vpc.backstage_vpc.cidr_block
  ip_protocol       = -1

  tags = local.tags
}
