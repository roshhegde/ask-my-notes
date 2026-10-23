# Ask My Notes: a low-cost serverless RAG chatbot on AWS

Upload your notes, ask questions, and get answers grounded in them, for well under $1 a month.

## How it works (the RAG idea in 30 seconds)

An LLM doesn't know what's in your notes. RAG (Retrieval-Augmented Generation) fixes that in two phases:

1. **Ingest (once per file):** split each document into small chunks, turn every chunk into an *embedding* (a list of numbers that captures its meaning), and store them.
2. **Ask (every question):** embed the question the same way, find the chunks whose numbers are closest (cosine similarity), and paste those chunks into the prompt so the model answers from them.

```
 upload ──► S3 notes/ ──► ingest Lambda ──► Titan embeddings ──► S3 index/
                                                                    │
 question ──► HTTP API ──► ask Lambda ──► embed + top-k search ◄────┘
                                │
                                └──► Nova Micro (or Claude Haiku) ──► answer
```

Why no vector database? OpenSearch Serverless costs about $175/month even when idle. For a few hundred chunks, loading the vectors into Lambda memory and doing the math in Python is instant and costs nothing extra.

## Build steps

| Step | What you add | What you learn |
|------|--------------|----------------|
| 1 (this one) | Terraform skeleton, $2 budget alarm, private S3 bucket | Terraform basics, cost guardrails |
| 2 | Ingest Lambda: chunking + Titan embeddings | Embeddings, S3 triggers, IAM least privilege |
| 3 | Ask Lambda + API Gateway HTTP API | Retrieval, prompt grounding, Bedrock calls |
| 4 | Tiny static web page | Putting it together |

## Rough monthly cost (hobby use)

| Service | Why it's cheap | Est. / month |
|---------|----------------|--------------|
| Lambda | 1M requests + 400k GB-s free every month | $0 |
| API Gateway HTTP API | $1 per million requests | < $0.01 |
| S3 | a few MB of notes and vectors | < $0.01 |
| Bedrock Titan embeddings | fractions of a cent per document | < $0.05 |
| Bedrock Nova Micro | ~300 questions | < $0.10 |
| AWS Budgets | first 2 budgets free | $0 |

Nothing here runs when idle. Check current prices on the AWS pricing pages before you rely on these numbers.

## Prerequisites

- An AWS account and the AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform 1.6 or newer
- In the Bedrock console (us-east-1), confirm access to **Titan Text Embeddings V2** and **Amazon Nova Micro**. You need this from step 2 on.

## Deploy step 1

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # put your email in it
terraform init
terraform plan     # read it: you should see 3 resources to add
terraform apply
```

Then open the email from AWS Budgets and confirm the subscription, otherwise alerts won't arrive.

Try the bucket:

```bash
BUCKET=$(terraform output -raw notes_bucket)
aws s3 cp ../README.md s3://$BUCKET/notes/
aws s3 ls s3://$BUCKET/notes/
```

## Teardown (do this whenever you're done for a while)

```bash
cd infra
terraform destroy
```

This deletes everything, including files in the bucket (`force_destroy = true`). Afterwards, run `aws s3 ls | grep ask-my-notes` to confirm nothing is left. Bedrock has no standing charges, so once you destroy there is nothing left to bill.
