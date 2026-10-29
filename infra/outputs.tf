output "notes_bucket" {
  description = "Upload your notes to s3://<this>/notes/"
  value       = aws_s3_bucket.notes.bucket
}

output "ask_url" {
  description = "POST {\"question\": \"...\"} here"
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/ask"
}
