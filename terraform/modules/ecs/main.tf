# ============================================================================
# ECS Cluster and Fargate Service
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = var.common_tags
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.name_prefix}-container"
      image     = var.container_image
      essential = true
      command   = ["python", "src/aws_abap_accelerator/enterprise_main.py"]

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENABLE_ENTERPRISE_MODE"
          value = tostring(var.enable_enterprise_mode)
        },
        {
          name  = "ENABLE_PRINCIPAL_PROPAGATION"
          value = tostring(var.enable_principal_propagation)
        },
        {
          name  = "ENABLE_OAUTH_FLOW"
          value = tostring(var.enable_oauth_flow)
        },
        {
          name  = "CREDENTIAL_PROVIDER"
          value = var.credential_provider
        },
        {
          name  = "SERVER_HOST"
          value = "0.0.0.0"
        },
        {
          name  = "SERVER_PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "DOCKER_CONTAINER"
          value = "true"
        },
        {
          name  = "SAP_HOST"
          value = var.sap_host
        },
        {
          name  = "SAP_INSTANCE_NUMBER"
          value = var.sap_instance_number
        },
        {
          name  = "SAP_CLIENT"
          value = var.sap_client
        },
        {
          name  = "SAP_LANGUAGE"
          value = var.sap_language
        },
        {
          name  = "SAP_SECURE"
          value = var.sap_secure
        },
        {
          name  = "SSL_VERIFY"
          value = var.ssl_verify
        },
        {
          name  = "SAP_PORT"
          value = var.sap_port
        },
        {
          name  = "LOG_LEVEL"
          value = var.log_level
        },
        {
          name  = "ENABLE_HTTP_REQUEST_LOGGING"
          value = var.enable_http_request_logging
        },
        {
          name  = "OAUTH_AUTH_ENDPOINT"
          value = var.oauth_auth_endpoint
        },
        {
          name  = "OAUTH_TOKEN_ENDPOINT"
          value = var.oauth_token_endpoint
        },
        {
          name  = "OAUTH_CLIENT_ID"
          value = var.oauth_client_id
        },
        {
          name  = "OAUTH_ISSUER"
          value = var.oauth_issuer
        },
        {
          name  = "SERVER_BASE_URL"
          value = var.server_base_url
        },
        {
          name  = "CA_SECRET_NAME"
          value = var.ca_secret_name
        },
        {
          name  = "SAP_ENDPOINTS_PARAMETER"
          value = var.sap_endpoints_parameter
        },
        {
          name  = "USER_EXCEPTIONS_PARAMETER"
          value = var.user_exceptions_parameter
        }
      ]

      secrets = concat(
        var.enable_principal_propagation && var.ca_certificate_secret_arn != "" ? [
          {
            name      = "CA_CERT"
            valueFrom = "${var.ca_certificate_secret_arn}:ca_certificate::"
          },
          {
            name      = "CA_KEY"
            valueFrom = "${var.ca_certificate_secret_arn}:ca_private_key::"
          }
        ] : [],
        var.oauth_secret_arn != "" ? [
          {
            name      = "OAUTH_CLIENT_SECRET"
            valueFrom = "${var.oauth_secret_arn}:client_secret::"
          }
        ] : [],
        var.jwt_signing_key_secret_arn != "" ? [
          {
            name      = "JWT_SIGNING_KEY"
            valueFrom = "${var.jwt_signing_key_secret_arn}:jwt_signing_key::"
          }
        ] : [],
        var.sap_credentials_secret_arn != "" ? [
          {
            name      = "SAP_USERNAME"
            valueFrom = "${var.sap_credentials_secret_arn}:SAP_USERNAME::"
          },
          {
            name      = "SAP_PASSWORD"
            valueFrom = "${var.sap_credentials_secret_arn}:SAP_PASSWORD::"
          }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python /app/src/aws_abap_accelerator/health_check.py || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = var.common_tags
}

# ECS Service
resource "aws_ecs_service" "app" {
  name                   = "${var.name_prefix}-service"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false # Use NAT gateway for outbound
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "${var.name_prefix}-container"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "ECS" # Rolling deployment
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  tags = var.common_tags
}

# Auto Scaling - Disabled for single task deployment (desired_count = 1)
# Uncomment for production with multiple tasks
/*
# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.desired_count * 4
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.name_prefix}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Auto Scaling Policy - Memory
resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "${var.name_prefix}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 80.0

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
*/
