import subprocess
import scout
import os

TF_DIR = "terraform"
TFVARS = "terraform/terraform.tfvars"


def run(cmd):
    subprocess.run(cmd, shell=True, check=True)


def get_current_region():
    if not os.path.exists(TFVARS):
        return None

    with open(TFVARS) as f:
        for line in f:
            if "target_region" in line:
                return line.split('"')[1]

    return None


def set_region(region):
    with open(TFVARS, "w") as f:
        f.write(f'target_region = "{region}"\n')


def terraform_apply(region):
    print(f"\nDeploying infrastructure in {region}")
    run(f"cd {TF_DIR} && terraform apply -auto-approve -var='target_region={region}'")


def terraform_destroy(region):
    print(f"\nDestroying infrastructure in {region}")
    run(f"cd {TF_DIR} && terraform destroy -auto-approve -var='target_region={region}'")


def main():

    cheapest_region = scout.find_cheapest()
    current_region = get_current_region()

    print(f"\nCurrent region: {current_region}")
    print(f"Cheapest region: {cheapest_region}")

    if cheapest_region is None:
        print("Scout failed to determine cheapest region.")
        return

    # First deployment
    if current_region is None:
        print("\nNo infrastructure detected. Deploying cheapest region.")
        set_region(cheapest_region)
        terraform_apply(cheapest_region)
        return

    # Already optimal
    if cheapest_region == current_region:
        print("\nAlready running in cheapest region.")
        return

    # Migration
    print(f"\nMigrating from {current_region} → {cheapest_region}")

    # 1️⃣ Deploy new infra
    set_region(cheapest_region)
    terraform_apply(cheapest_region)

    # 2️⃣ Destroy old infra
    terraform_destroy(current_region)

    print("\nMigration complete.")


if __name__ == "__main__":
    main()