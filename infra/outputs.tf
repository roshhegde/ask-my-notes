output "notes_bucket" {
  description = "Upload your notes to s3://<this>/notes/"
  value       = aws_s3_bucket.notes.bucket
}
