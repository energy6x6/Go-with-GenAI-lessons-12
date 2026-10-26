locals {
  functions = {
    webhook   = { timeout = 10, memory = 256 }
    thumbnail = { timeout = 30, memory = 512 }
    reader    = { timeout = 10, memory = 256 }
  }
  routes = {
    webhook = { resource_id = aws_api_gateway_resource.webhook.id, path = "/webhook" }
    reader  = { resource_id = aws_api_gateway_resource.normalize.id, path = "/readers/normalize" }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "covers" {
  bucket        = var.covers_bucket
  force_destroy = false
}

resource "aws_s3_bucket" "thumbnails" {
  bucket        = var.thumbnails_bucket
  force_destroy = false
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_group" "function" {
  for_each          = local.functions
  name              = "/aws/lambda/${var.project_name}-${each.key}"
  retention_in_days = 7
}

resource "aws_iam_role" "function" {
  for_each           = local.functions
  name               = "${var.project_name}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "logs" {
  for_each = local.functions
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.function[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  for_each = local.functions
  name     = "write-own-logs"
  role     = aws_iam_role.function[each.key].id
  policy   = data.aws_iam_policy_document.logs[each.key].json
}

data "aws_iam_policy_document" "thumbnail_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.covers.arn}/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.thumbnails.arn}/*"]
  }
}

resource "aws_iam_role_policy" "thumbnail_s3" {
  name   = "read-covers-write-thumbnails"
  role   = aws_iam_role.function["thumbnail"].id
  policy = data.aws_iam_policy_document.thumbnail_s3.json
}

resource "aws_lambda_function" "function" {
  for_each         = local.functions
  function_name    = "${var.project_name}-${each.key}"
  role             = aws_iam_role.function[each.key].arn
  runtime          = "provided.al2023"
  architectures    = [var.lambda_architecture]
  handler          = "bootstrap"
  filename         = "${path.module}/../build/${each.key}.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/${each.key}.zip")
  timeout          = each.value.timeout
  memory_size      = each.value.memory
  environment {
    variables = each.key == "thumbnail" ? { OUTPUT_BUCKET = aws_s3_bucket.thumbnails.bucket } : {}
  }
  depends_on = [aws_iam_role_policy.logs, aws_iam_role_policy.thumbnail_s3]
}

resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project_name}-api"
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_resource" "readers" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "readers"
}

resource "aws_api_gateway_resource" "normalize" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.readers.id
  path_part   = "normalize"
}

resource "aws_api_gateway_method" "post" {
  for_each      = local.routes
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value.resource_id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "http" {
  for_each                = local.routes
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.post[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.function[each.key].invoke_arn
}

resource "aws_lambda_permission" "apigateway" {
  for_each      = local.routes
  statement_id  = "AllowAPIGatewayPOST"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/${var.stage_name}/POST${each.value.path}"
}

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode([
      for key, route in local.routes : {
        path   = route.path
        uri    = aws_api_gateway_integration.http[key].uri
        method = aws_api_gateway_method.post[key].http_method
        type   = aws_api_gateway_integration.http[key].type
      }
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_lambda_permission.apigateway]
}

resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
  stage_name    = var.stage_name
}

resource "aws_lambda_permission" "s3_thumbnail" {
  statement_id   = "AllowCoversS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.function["thumbnail"].function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.covers.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "covers" {
  bucket = aws_s3_bucket.covers.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.function["thumbnail"].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "covers/"
  }
  depends_on = [aws_lambda_permission.s3_thumbnail]
}
