import subprocess
import scout


def get_current_region():
    with open("terraform/terraform.tfvars") as f:
        for line in f:
            if "target_region" in line:
                return line.split('"')[1]


def set_region(region):
    with open("terraform/terraform.tfvars", "w") as f:
        f.write(f'target_region = "{region}"')

    subprocess.run(["git", "add", "."])
    subprocess.run(["git", "commit", "-m", f"Nomad migration to {region}"])
    subprocess.run(["git", "push"])


def main():

    cheapest_region = scout.find_cheapest()
    current_region = get_current_region()

    print(f"\nCurrent region: {current_region}")
    print(f"Cheapest region: {cheapest_region}")

    if cheapest_region is None:
        print("Scout failed to determine cheapest region.")
        return

    if current_region is None:
        print("\nNo infrastructure detected. Setting cheapest region.")
        set_region(cheapest_region)
        return

    if cheapest_region == current_region:
        print("\nAlready running in cheapest region.")
        return

    print(f"\nMigrating from {current_region} → {cheapest_region}")

    set_region(cheapest_region)

    print("Region updated. CI/CD will migrate infrastructure.")


if __name__ == "__main__":
    main()