# ============================================================================
# Security Groups for ALB and ECS
# ============================================================================

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-alb-sg"
    }
  )
}

# Allow HTTP traffic to ALB
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from specified CIDR blocks"

  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_cidr_blocks[0] # Primary CIDR

  tags = var.common_tags
}

# Allow HTTPS traffic to ALB (if certificate is configured)
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from specified CIDR blocks"

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_cidr_blocks[0] # Primary CIDR

  tags = var.common_tags
}

# Allow all outbound traffic from ALB
resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = var.common_tags
}

# ============================================================================
# Security Group for ECS Tasks
# ============================================================================

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-ecs-sg"
    }
  )
}

# Allow traffic from ALB to ECS tasks
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id = aws_security_group.ecs.id
  description       = "Allow traffic from ALB"

  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = var.common_tags
}

# Allow all outbound traffic from ECS (to reach SAP systems)
resource "aws_vpc_security_group_egress_rule" "ecs_egress" {
  security_group_id = aws_security_group.ecs.id
  description       = "Allow all outbound traffic (SAP, AWS APIs)"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = var.common_tags
}
