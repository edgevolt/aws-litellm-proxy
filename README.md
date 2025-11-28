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
* **Resilient:** Automated "Self-Healing" deployment script via Python.

## 🛠 Prerequisites
* AWS CLI (Configured with Administrator Access)
* Terraform v1.0+
* Docker

## 💻 Usage

### 1. Automated Deployment
The included `demo.py` script handles the entire lifecycle:
1. Provisions Infrastructure (Terraform)
2. Builds & Pushes Docker Image
3. Deploys to ECS Fargate
4. Waits for Stability
5. Runs Integration Tests

```bash
python3 demo.py
```

### 2. Manual Testing
Once running, you can hit the endpoint using OpenAI-compatible formats:

```bash
curl -X POST http://YOUR_LB_IP:4000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bedrock-cohere", 
    "messages": [{ "role": "user", "content": "Hello!" }] 
  }'
```

## 🧹 Cleanup
To destroy all resources and stop billing:
```bash
terraform destroy -auto-approve
```
