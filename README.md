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
- Nothing to enable in Bedrock: Titan and Nova models switch on automatically the first time your account calls them.

## Deploy step 1

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # put your email in it
terraform init
terraform plan     # read it: you should see 3 resources to add
terraform apply
```

AWS Budgets emails you directly, so there's no subscription to confirm. To check that the budget exists, open Billing → Budgets in the console.

Try the bucket:

```bash
BUCKET=$(terraform output -raw notes_bucket)
aws s3 cp ../README.md s3://$BUCKET/notes/
aws s3 ls s3://$BUCKET/notes/
```

## Deploy step 2: ingest

Bedrock models are enabled automatically on first use, so just run:

```bash
cd infra
terraform apply          # adds the ingest Lambda, its IAM role, log group and S3 trigger
BUCKET=$(terraform output -raw notes_bucket)
aws s3 cp ../README.md s3://$BUCKET/notes/readme.md
sleep 20
aws s3 ls s3://$BUCKET/index/                       # readme.md.json should appear
aws logs tail /aws/lambda/ask-my-notes-ingest --since 5m
```

What happened: S3 fired an event, the Lambda split the file into ~1,000-character chunks that overlap by 150, sent each chunk to Titan, and saved the text plus a 256-number vector per chunk to `index/`. Download the JSON and look at it to see what an embedding looks like.

Only `.txt` and `.md` are supported for now. Each file is capped at 200 chunks so one huge upload can't run up a bill.

Run the unit tests locally with `cd lambdas/ingest && python -m pytest`.

## Deploy step 3: ask questions

Nova Micro switches on automatically the first time the ask Lambda calls it. Run:

```bash
cd infra
terraform apply          # adds the ask Lambda and an HTTP API
URL=$(terraform output -raw ask_url)
curl -s -X POST "$URL" -H 'content-type: application/json' \
  -d '{"question": "Why does this project avoid OpenSearch?"}'
```

You should get back JSON with an `answer` and the `sources` it used.

What happened: the Lambda embedded your question with the same Titan model, scored every stored chunk by cosine similarity (how closely two vectors point the same way), kept the top 4, and sent them to Nova Micro with instructions to answer only from those notes. That is the whole RAG idea.

Things to try:
- Ask something your notes don't cover. The model should say it doesn't know.
- Change `chat_model_id` in `terraform.tfvars` to a Claude Haiku model ID and compare the answers. Haiku costs more per question.
- Check token usage per question with `aws logs tail /aws/lambda/ask-my-notes-ask --since 10m`.

The API has no login, so it is throttled to 1 request per second and questions are capped at 500 characters. Don't share the URL publicly, and run `terraform destroy` when you're not using it.

Unit tests: `cd lambdas/ask && python -m pytest`.

## Teardown (do this whenever you're done for a while)

```bash
cd infra
terraform destroy
```

This deletes everything, including files in the bucket (`force_destroy = true`). Afterwards, run `aws s3 ls | grep ask-my-notes` to confirm nothing is left. Bedrock has no standing charges, so once you destroy there is nothing left to bill.
