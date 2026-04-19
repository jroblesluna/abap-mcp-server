# ============================================================================
# IAM Roles and Policies for ECS Fargate
# ============================================================================

# ECS Task Execution Role (for pulling images, writing logs)
resource "aws_iam_role" "task_execution" {
  name = "${var.name_prefix}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.common_tags
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for accessing Secrets Manager
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "${var.name_prefix}-secrets-access"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.name_prefix}/*",
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:mcp/abap-mcp-server/*"
        ]
      }
    ]
  })
}

# ============================================================================
# ECS Task Role (for application runtime permissions)
# ============================================================================

resource "aws_iam_role" "task_role" {
  name = "${var.name_prefix}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.common_tags
}

# Policy for accessing Secrets Manager (CA certificates, OAuth secrets)
resource "aws_iam_role_policy" "task_secrets_access" {
  name = "${var.name_prefix}-task-secrets"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.name_prefix}/*",
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:mcp/abap-mcp-server/*"
        ]
      }
    ]
  })
}

# Policy for accessing Parameter Store (SAP endpoints, user mappings)
resource "aws_iam_role_policy" "task_parameter_store" {
  name = "${var.name_prefix}-task-parameters"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${var.name_prefix}/*",
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/abap-mcp-server/*",
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/mcp/abap-mcp-server/*"
        ]
      }
    ]
  })
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "task_cloudwatch" {
  name = "${var.name_prefix}-task-cloudwatch"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/${var.name_prefix}*"
      }
    ]
  })
}

# Policy for ECS Exec (SSM)
resource "aws_iam_role_policy" "task_ecs_exec" {
  name = "${var.name_prefix}-task-ecs-exec"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}
