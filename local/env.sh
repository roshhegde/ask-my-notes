# Point the AWS CLI in this terminal at Floci instead of real AWS.
# Usage:  source local/env.sh
unset AWS_PROFILE
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
echo "AWS CLI now talks to Floci (local). Open a new terminal to go back to real AWS."
