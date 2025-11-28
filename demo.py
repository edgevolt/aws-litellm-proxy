import subprocess
import time
import json
import sys
import urllib.request
import urllib.error

# --- Configuration ---
CLUSTER_NAME = "litellm-cluster"
SERVICE_NAME = "litellm-service"
REGION = "us-east-1"
APP_PORT = 4000

# ANSI Colors for professional output
GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
BOLD = "\033[1m"
RESET = "\033[0m"

def log(message, level="INFO"):
    if level == "INFO":
        print(f"\n{BOLD}[INFO]{RESET} {message}")
    elif level == "SUCCESS":
        print(f"      {GREEN}✅ {message}{RESET}")
    elif level == "ERROR":
        print(f"      {RED}❌ {message}{RESET}")

def run_command(command, capture_output=True):
    try:
        result = subprocess.run(
            command, 
            check=True, 
            shell=False, 
            text=True, 
            capture_output=capture_output
        )
        if result.stdout:
            return result.stdout.strip()
        return ""
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {' '.join(command)}", "ERROR")
        if e.stderr:
            print(f"Error details: {e.stderr}")
        sys.exit(1)

def main():
    print("========================================================")
    print(f"   🚀 {BOLD}STARTING PYTHON AUTOMATED DEPLOYMENT & TEST{RESET} 🚀")
    print("========================================================")

    # 1. Terraform
    log("Provisioning AWS Infrastructure (Terraform)...")
    run_command(["terraform", "init"])
    run_command(["terraform", "apply", "-auto-approve"], capture_output=False)
    
    ecr_repo_url = run_command(["terraform", "output", "-raw", "ecr_repo_url"])
    log(f"Infrastructure Ready. Repo: {ecr_repo_url}", "SUCCESS")

    # 2. Docker Build & Push
    log("Building and Shipping Container...")
    
    login_password = run_command(["aws", "ecr", "get-login-password", "--region", REGION])
    
    login_proc = subprocess.Popen(
        ["docker", "login", "--username", "AWS", "--password-stdin", ecr_repo_url],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = login_proc.communicate(input=login_password)
    
    if login_proc.returncode != 0:
        log(f"Docker Login Failed: {stderr}", "ERROR")
        sys.exit(1)

    run_command(["docker", "build", "-t", "litellm-lab", "."])
    run_command(["docker", "tag", "litellm-lab:latest", f"{ecr_repo_url}:latest"])
    run_command(["docker", "push", f"{ecr_repo_url}:latest"])
    log("Image Pushed to ECR.", "SUCCESS")

    # 3. ECS Deployment
    log("Updating Fargate Service...")
    run_command([
        "aws", "ecs", "update-service",
        "--cluster", CLUSTER_NAME,
        "--service", SERVICE_NAME,
        "--force-new-deployment",
        "--no-cli-pager"
    ])
    log("Deployment Triggered.", "SUCCESS")

    # 4. Polling
    log("Waiting for Task to Provision (~2-3 mins)...")
    task_arn = None
    
    while True:
        list_json = run_command(["aws", "ecs", "list-tasks", "--cluster", CLUSTER_NAME, "--service-name", SERVICE_NAME, "--output", "json"])
        tasks = json.loads(list_json).get("taskArns", [])

        if tasks:
            task_arn = tasks[0]
            desc_json = run_command(["aws", "ecs", "describe-tasks", "--cluster", CLUSTER_NAME, "--tasks", task_arn, "--output", "json"])
            task_details = json.loads(desc_json)["tasks"][0]
            status = task_details["lastStatus"]
            
            sys.stdout.write(f"\r      Current Status: {status}...")
            sys.stdout.flush()

            if status == "RUNNING":
                print("") 
                log("Task is RUNNING!", "SUCCESS")
                break
            
            if status == "STOPPED":
                print("")
                reason = task_details.get("stoppedReason", "Unknown")
                log(f"Task Crashed! Reason: {reason}", "ERROR")
                sys.exit(1)
        
        time.sleep(5)

    # 5. Get IP
    log("Fetching Public IP...")
    time.sleep(5) 
    
    desc_json = run_command(["aws", "ecs", "describe-tasks", "--cluster", CLUSTER_NAME, "--tasks", task_arn, "--output", "json"])
    task_details = json.loads(desc_json)["tasks"][0]
    
    eni_id = None
    for attachment in task_details["attachments"]:
        for detail in attachment["details"]:
            if detail["name"] == "networkInterfaceId":
                eni_id = detail["value"]
                break
    
    if not eni_id:
        log("Could not find Network Interface ID.", "ERROR")
        sys.exit(1)

    eni_json = run_command(["aws", "ec2", "describe-network-interfaces", "--network-interface-ids", eni_id, "--output", "json"])
    public_ip = json.loads(eni_json)["NetworkInterfaces"][0]["Association"]["PublicIp"]
    log(f"Target IP Found: {public_ip}", "SUCCESS")

    # 6. Run Tests with FULL DEBUG OUTPUT
    log("Running Validation Tests (High Verbosity)...")
    print("      (Waiting 15s for Python App to initialize port 4000...)")
    time.sleep(15)
    print("--------------------------------------------------------")

    # UPDATED PROMPTS: More direct instructions for the smaller models
    models_to_test = [
        ("bedrock-cohere", "Reply with exactly this phrase: 'Cohere is online'"),
        ("bedrock-llama", "Reply with exactly this phrase: 'Llama is online'"),
        ("bedrock-titan", "Reply with exactly this phrase: 'Titan is online'"),
        ("bedrock-titan-lite", "You are a test bot. Reply with this exact phrase: 'Titan Lite is online'")
    ]

    base_url = f"http://{public_ip}:{APP_PORT}/chat/completions"

    for model, prompt in models_to_test:
        print(f"👉 Testing Model: {BOLD}{CYAN}{model}{RESET}")
        print(f"   Prompt: \"{prompt}\"")
        
        payload = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}]
        }).encode('utf-8')

        req = urllib.request.Request(base_url, data=payload, headers={'Content-Type': 'application/json'})

        start_time = time.time()
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                latency = (time.time() - start_time) * 1000
                response_body = response.read().decode('utf-8')
                parsed = json.loads(response_body)
                
                if "choices" in parsed:
                    print(f"   {GREEN}✅ STATUS: SUCCESS{RESET} ({latency:.0f}ms)")
                    
                    # Print the nice answer
                    content = parsed['choices'][0]['message']['content']
                    print(f"   💬 ANSWER: {BOLD}{content}{RESET}")
                    
                    # Print the RAW EVIDENCE (Technical Proof)
                    print(f"   {YELLOW}🔍 DEBUG (Raw JSON):{RESET}")
                    # Pretty print the JSON with indentation
                    print(json.dumps(parsed, indent=4))
                else:
                    print(f"   {RED}❌ STATUS: UNEXPECTED RESPONSE{RESET}")
                    print(f"   {response_body}")

        except urllib.error.HTTPError as e:
            print(f"   {RED}❌ STATUS: FAILED (HTTP {e.code}){RESET}")
            print(f"   {e.read().decode('utf-8')}")
        except Exception as e:
            print(f"   {RED}❌ STATUS: FAILED (Connection Error){RESET}")
            print(f"   {str(e)}")
        
        print("--------------------------------------------------------")

    print(f"🎉 {BOLD}DEMO COMPLETE!{RESET} Infrastructure is live at {public_ip}")
    print("   (Don't forget to run 'terraform destroy' when finished)")

if __name__ == "__main__":
    main()
