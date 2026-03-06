import subprocess
import scout

CURRENT_REGION = "eu-central-1"

cheapest_region = scout.find_cheapest()

if cheapest_region == CURRENT_REGION:
    print("Already running in cheapest region. No migration needed.")
else:
    print(f"Migrating infrastructure to {cheapest_region}")

    with open("terraform/terraform.tfvars", "w") as f:
        f.write(f'target_region = "{cheapest_region}"')

    subprocess.run(["git", "add", "."])
    subprocess.run(["git", "commit", "-m", f"Nomad migration to {cheapest_region}"])
    subprocess.run(["git", "push"])