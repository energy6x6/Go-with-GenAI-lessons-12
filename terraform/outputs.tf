output "api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "webhook_url_floci" {
  value = "${var.floci_endpoint}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_/webhook"
}

output "reader_url_floci" {
  value = "${var.floci_endpoint}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_/readers/normalize"
}

output "function_names" {
  value = { for key, function in aws_lambda_function.function : key => function.function_name }
}
