# One private bucket holds everything:
#   notes/    your uploaded PDFs and text files
#   index/    the chunks + embeddings we build in step 2
resource "aws_s3_bucket" "notes" {
  bucket_prefix = "${var.project_name}-"

  # Lets `terraform destroy` delete the bucket even when it has files in it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "notes" {
  bucket                  = aws_s3_bucket.notes.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
