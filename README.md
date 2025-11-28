# Serverless Multi-Model AI Proxy on AWS

This project demonstrates a production-grade deployment of **LiteLLM** as a secure AI Gateway on AWS. It allows applications to access multiple Bedrock models (Cohere, Llama 3, Titan) through a single OpenAI-compatible API endpoint.

## 🏗 Architecture
* **Infrastructure as Code:** Terraform
* **Container Orchestration:** AWS ECS (Fargate Spot)
* **API Gateway:** LiteLLM (Python)
* **Security:** IAM Roles (Zero Static Keys) & Dynamic IP Whitelisting

## 🚀 Features
* **Multi-Model Routing:** Seamlessly routes traffic between Anthropic, Cohere, Meta, and Amazon models.
* **Cost Optimized:** Uses Fargate Spot instances to reduce compute costs by ~70%.
* **Secure by Default:** * No hardcoded AWS keys (uses IAM Task Roles).
    * Network locked down to the administrator's specific IP via Terraform.
* **Resilient:** Automated "Self-Healing" deployment scripts (Python & Bash).

## 🛠 Prerequisites
* AWS CLI (Configured with Administrator Access)
* Terraform v1.0+
* Docker
* Python 3 (Optional, for the Python deployment script)

## 💻 Usage

You can deploy the entire environment using either the Python script (recommended for better error handling) or the Bash script.

### Option A: Python Deployment (Recommended)
The \`demo.py\` script provides structured logging, JSON parsing for test evidence, and robust error handling.

\`\`\`bash
python3 demo.py
\`\`\`

### Option B: Bash Deployment
For environments where Python is not available, the shell script provides the same "One-Click" deployment capability.

\`\`\`bash
chmod +x demo.sh
./demo.sh
\`\`\`

---

### Manual Testing
Once the infrastructure is running, you can hit the endpoint using OpenAI-compatible formats:

\`\`\`bash
# Replace YOUR_LB_IP with the Public IP from the deployment output
curl -X POST http://YOUR_LB_IP:4000/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "bedrock-cohere", 
    "messages": [{ "role": "user", "content": "Hello!" }] 
  }'
\`\`\`

## 🧹 Cleanup
To destroy all resources and stop billing, run:
\`\`\`bash
terraform destroy -auto-approve
\`\`\`
