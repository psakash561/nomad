import os
import subprocess

# THE SIMULATION
price_us = 0.25  # Simulating a price spike!
price_eu = 0.16  # Frankfurt is now cheaper

if price_eu < price_us:
    print(f"⚠️ US Price (${price_us}) is too high! Moving to Frankfurt (${price_eu})...")
    
    # This command tells Terraform to change the region variable and apply
    cmd = [
        "terraform", "apply", 
        "-var", "target_region=eu-central-1", 
        "-auto-approve"
    ]
    
    subprocess.run(cmd)
    print("✅ Migration Complete. Nomad is now in Europe.")
else:
    print("Market is stable. Staying in the US.")