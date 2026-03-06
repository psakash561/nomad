import boto3
import json

INSTANCE_TYPE = "t3.medium"

REGIONS = [
    "us-east-1",
    "us-west-2",
    "eu-central-1",
    "eu-west-1",
    "ap-south-1"
]

def get_price(region):
    ec2 = boto3.client("ec2", region_name=region)

    prices = ec2.describe_spot_price_history(
        InstanceTypes=[INSTANCE_TYPE],
        ProductDescriptions=["Linux/UNIX"],
        MaxResults=1
    )

    if prices["SpotPriceHistory"]:
        return float(prices["SpotPriceHistory"][0]["SpotPrice"])

    return None


def find_cheapest():
    results = {}

    for region in REGIONS:
        try:
            price = get_price(region)
            if price:
                results[region] = price
                print(f"{region} -> ${price}")
        except Exception as e:
            print(f"Error in {region}: {e}")

    if results:
        cheapest = min(results, key=results.get)
        print("\nCheapest Region:", cheapest)
        print("Price:", results[cheapest])

        return cheapest

if __name__ == "__main__":
    find_cheapest()