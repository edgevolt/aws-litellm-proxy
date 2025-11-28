#!/bin/bash
set -e # Exit immediately if infrastructure setup fails

# --- Configuration ---
CLUSTER_NAME="litellm-cluster"
SERVICE_NAME="litellm-service"
REGION="us-east-1"

echo "========================================================"
echo "   🚀 STARTING AUTOMATED DEPLOYMENT & EVIDENCE COLLECTION 🚀"
echo "========================================================"

# 1. Terraform: Build Infrastructure
echo -e "\n[1/6] 🏗️  Provisioning AWS Infrastructure (Terraform)..."
terraform init > /dev/null
terraform apply -auto-approve
REPO_URL=$(terraform output -raw ecr_repo_url)
echo "      ✅ Infrastructure Ready. Repo: $REPO_URL"

# 2. Docker: Build & Push
echo -e "\n[2/6] 🐳 Building and Shipping Container..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPO_URL > /dev/null 2>&1
docker build -t litellm-lab . > /dev/null 2>&1
docker tag litellm-lab:latest $REPO_URL:latest
docker push $REPO_URL:latest > /dev/null 2>&1
echo "      ✅ Image Pushed to ECR."

# 3. ECS: Update Service
echo -e "\n[3/6] 🔄 Updating Fargate Service..."
aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --force-new-deployment --no-cli-pager > /dev/null
echo "      ✅ Deployment Triggered."

# 4. Polling: Wait for Task to be RUNNING
echo -e "\n[4/6] ⏳ Waiting for Task to Provision (This takes ~2-3 mins)..."
TASK_ARN=""
while true; do
    TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --query "taskArns[0]" --output text)
    
    if [ "$TASK_ARN" != "None" ]; then
        STATUS=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query "tasks[0].lastStatus" --output text)
        echo -ne "      Current Status: $STATUS...\r"
        
        if [ "$STATUS" == "RUNNING" ]; then
            echo -e "\n      ✅ Task is RUNNING!"
            break
        fi
        
        if [ "$STATUS" == "STOPPED" ]; then
            echo -e "\n      ❌ Task Crashed! Checking logs..."
            aws logs get-log-events --log-group-name /ecs/litellm --log-stream-name $(aws logs describe-log-streams --log-group-name /ecs/litellm --order-by LastEventTime --descending --limit 1 --query 'logStreams[0].logStreamName' --output text) --limit 20
            exit 1
        fi
    fi
    sleep 5
done

# 5. Networking: Fetch Public IP
echo -e "\n[5/6] 🌐 Fetching Public IP..."
sleep 5 # Buffer for network interface attachment
ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
echo "      ✅ Target IP Found: $PUBLIC_IP"

# 6. Verification: Run Tests & Show Evidence
echo -e "\n[6/6] 🧪 Running Validation Tests (With Evidence)..."
echo "      (Waiting 15s for Python App to initialize port 4000...)"
sleep 15
echo "========================================================"

# DISABLE "Exit on Error" so we can see all test results
set +e

# Function to run test and print output
test_model() {
    MODEL=$1
    PROMPT=$2
    echo -e "👉 Testing Model: \033[1m$MODEL\033[0m"
    echo "   Prompt: \"$PROMPT\""
    
    # Run curl and capture output
    RESPONSE=$(curl --max-time 20 -s -X POST http://$PUBLIC_IP:4000/chat/completions \
      -H "Content-Type: application/json" \
      -d "{ \"model\": \"$MODEL\", \"messages\": [{ \"role\": \"user\", \"content\": \"$PROMPT\" }] }")
    
    # Check if successful
    if echo "$RESPONSE" | grep -q "content"; then
        echo -e "   ✅ STATUS: \033[32mSUCCESS\033[0m"
        echo "   📜 API RESPONSE:"
        echo "$RESPONSE"
    else
        echo -e "   ❌ STATUS: \033[31mFAILED\033[0m"
        echo "   🔍 ERROR OUTPUT:"
        echo "$RESPONSE"
    fi
    echo "--------------------------------------------------------"
}

test_model "bedrock-cohere" "Say 'Cohere is online' if you can hear me."
test_model "bedrock-llama" "Say 'Llama is online' if you can hear me."
test_model "bedrock-titan" "Say 'Titan is online' if you can hear me."
test_model "bedrock-titan-lite" "Say 'Titan Lite is online' if you can hear me."

echo "🎉 DEMO COMPLETE! Infrastructure is live at $PUBLIC_IP"
echo "   (Don't forget to run 'terraform destroy' when finished)"
