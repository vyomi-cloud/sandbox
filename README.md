# Vyomi Cloud Sandbox

Run a faithful **AWS simulator** — S3, DynamoDB, SQS, SNS, IAM, KMS, Secrets Manager, RDS —
entirely inside a **GitHub Codespace**. No local install, no cloud account, no bill. Point your
existing `boto3` / `aws-cli` code at it and validate real application logic.

> _Build for the cloud, without the cloud._

## Open it

Click **Code → Codespaces → Create codespace**, or use a launch link from your Vyomi admin.
The sandbox boots the `aws-core` profile automatically (~1–2 min on first create), then forwards
port **9000** — open it to reach the console.

## Use it — smoke test S3 · RDS · EC2

```bash
EP="$CLOUDLEARN_PUBLIC_URL"          # or http://localhost:9000 inside the Codespace

# S3
aws --endpoint-url "$EP" s3 mb s3://demo
aws --endpoint-url "$EP" s3 ls

# RDS (create a Postgres instance, then list)
aws --endpoint-url "$EP" rds create-db-instance \
  --db-instance-identifier demo-db --engine postgres \
  --db-instance-class db.t3.micro --allocated-storage 20 \
  --master-username admin --master-user-password secret99
aws --endpoint-url "$EP" rds describe-db-instances

# EC2 (launches as a real container on the Codespace's docker-in-docker)
aws --endpoint-url "$EP" ec2 run-instances --image-id ami-ubuntu --instance-type t3.micro
aws --endpoint-url "$EP" ec2 describe-instances
```

`$CLOUDLEARN_PUBLIC_URL` is the forwarded `https://<codespace>-9000.app.github.dev` address
(external SDKs on your laptop can hit it too, when the port is set to public). Inside the
Codespace, `http://localhost:9000` works directly.

## What's inside

| | |
|--|--|
| **Services** | S3 · DynamoDB · SQS · SNS · IAM · KMS · Secrets Manager · RDS · **EC2** |
| **Compute** | Real EC2 instances as sibling Docker containers (docker-in-docker) |
| **Default tier** | Unlicensed = Free → **1 VM + 1 RDS + 1 bucket** per space (enough to smoke-test). Activate Pro for 10 VMs. |
| **TTL** | 8 h by default — the sandbox stops itself after the window (`VYOMI_SANDBOX_TTL`) |
| **Cost** | $0 on a personal account's free Codespaces quota; metered in the Vyomi admin cost dashboard |

## Activate a paid tier (optional)

The console's **Activate** button runs the standard device flow (GitHub sign-in). Enterprises can
instead pre-seed a license by setting the `VYOMI_LICENSE_JWT` **Codespaces secret** — seats then
activate with zero clicks.

---

Profiles, TTL, and compute size are managed by your Vyomi enterprise admin. This template is
published from the appliance repo (`appliance/codespace/`); do not edit in place.
