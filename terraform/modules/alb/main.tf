# ============================================================================
# Application Load Balancer (ALB)
# Using ALB with sticky sessions for proper MCP session management
# Sticky sessions ensure requests route to the same backend task
# ============================================================================

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = true  # Internal ALB - only accessible within VPC
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [var.alb_security_group_id]

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-alb"
    }
  )
}

# Target Group for ECS tasks
resource "aws_lb_target_group" "app" {
  name        = "${var.name_prefix}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-499"  # Accept 404 from FastMCP root path
  }

  # Sticky sessions disabled - not recommended for multiple tasks with stateful sessions
  # MCP sessions are stateful and stored in task memory
  # Without sticky sessions, requests may route to different tasks causing session loss
  stickiness {
    enabled         = false
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
  }

  deregistration_delay = 30

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-tg"
    }
  )
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.common_tags
}

# HTTP Listener - redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.common_tags
}
