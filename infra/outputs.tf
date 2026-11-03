output "notes_bucket" {
  description = "Upload your notes to s3://<this>/notes/"
  value       = aws_s3_bucket.notes.bucket
}

output "ask_url" {
  description = "POST {\"question\": \"...\"} here"
  # Floci serves HTTP APIs under localhost:4566/execute-api/<id>/<stage>/...
  value = local.use_floci ? "${local.floci_url}/execute-api/${aws_apigatewayv2_api.http.id}/$default/ask" : "${aws_apigatewayv2_api.http.api_endpoint}/ask"
}
