import subprocess
import scout
import json
import os

TF_DIR = "terraform"
CURRENT_REGION_FILE = "current_region.txt"

def run(cmd):
    subprocess.run(cmd, shell=True, check=True)

def get_current_region():
    if os.path.exists(CURRENT_REGION_FILE):
        with open(CURRENT_REGION_FILE) as f:
            return f.read().strip()
    return None

def set_current_region(region):
    with open(CURRENT_REGION_FILE, "w") as f:
        f.write(region)

def terraform_apply(region):
    print(f"Deploying infrastructure in {region}")
    run(f"cd {TF_DIR} && terraform apply -auto-approve -var='target_region={region}'")

def terraform_destroy(region):
    print(f"Destroying infrastructure in {region}")
    run(f"cd {TF_DIR} && terraform destroy -auto-approve -var='target_region={region}'")

def main():

    cheapest_region = scout.find_cheapest()
    current_region = get_current_region()

    print(f"Current region: {current_region}")
    print(f"Cheapest region: {cheapest_region}")

    if cheapest_region == current_region:
        print("Already running in cheapest region.")
        return

    # 1️⃣ Deploy new infrastructure
    terraform_apply(cheapest_region)

    # 2️⃣ Destroy old infrastructure
    if current_region:
        terraform_destroy(current_region)

    # 3️⃣ Update region tracking
    set_current_region(cheapest_region)

    print("Migration complete.")

if __name__ == "__main__":
    main()