# Azure infrastructure

This assessment uses validation only. Nothing is deployed to Azure.

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

Container Apps Consumption runs the API and connects to private PostgreSQL 16. The app's managed identity reads its database connection string from Key Vault. Logs go to an existing Log Analytics workspace.

- `main.tf`: resource group and tags.
- `app.tf`: compute, HTTPS ingress and readiness check.
- `database.tf`: PostgreSQL server and application database.
- `secrets.tf`: Key Vault, application identity and secret-read permission.
- `variables.tf`: settings and existing network/workspace IDs.
- `outputs.tf`: service addresses, with no secret values.

This is one small root module. Separate modules would add little reuse here.

## Existing infrastructure

Supply separate subnets in the same or connected virtual networks: one reserved for Container Apps workload profiles and delegated to `Microsoft.App/environments`, and one delegated to `Microsoft.DBforPostgreSQL/flexibleServers`. The PostgreSQL private DNS zone must already be linked to the application network. Subnet sizing, routes and firewall rules must meet Azure's requirements.

Supply an existing Log Analytics workspace. The published image must be accessible without registry credentials; use an immutable digest. Private ACR would need a registry identity and pull permission, which this sketch does not configure.

## Database and secret setup

`deploy_app` defaults to false because a new database has no application tables or application login. For a real deployment:

1. Provision infrastructure with application creation disabled.
2. From a runner with private database connectivity, initialize the schema and run migrations. Use a separate migration login with schema-change permissions. Do not repeatedly load assessment seed data into production.
3. Create a restricted application login with the required table and sequence permissions. An authorized bootstrap process stores its TLS connection string as `orders-db-url` in this Key Vault. Use `sslmode=verify-full` and ensure the container trusts the server certificate chain. Keep the administrator credential out of the app.
4. Enable `deploy_app` after the secret exists and RBAC has propagated. The container reads `DB_URL` through its Key Vault reference.

Database grants and the bootstrap process are deployment prerequisites, not implemented Terraform resources. The app identity can read secrets but cannot create them. A separate deployment identity needs resource provisioning and role assignment permissions; the bootstrap identity needs secret-write permission.

## State and secrets

No backend is configured for validation. For deployment, use an Azure Storage backend with a separate state key per environment, restricted RBAC, encryption, blob lease locking and versioning. Authenticate CI with workload identity federation. Provision the backend separately before initializing against it.

Supply the administrator password through a protected pipeline variable such as `TF_VAR_database_admin_password`. Sensitive variables hide normal CLI output; the password still exists in state and saved plans. Restrict access to both. The application connection string is populated outside Terraform so Terraform does not manage its value. Never commit state, plans or secret variable files. Commit `.terraform.lock.hcl` for reproducible provider selection.

## Cost and production limits

Consumption avoids operating a new AKS cluster for a single service. The app uses 0.25 CPU and 0.5 GiB, with zero to two replicas by default. Scale-to-zero trades idle consumption for cold starts; database, logs and networking still incur costs. If the company already operates AKS, compare its marginal cost before adding another platform.

The burstable database, seven-day backups and no high availability are development choices. Production sizing, minimum replicas, availability and restore testing need workload and recovery requirements. PostgreSQL is open source; the managed service reduces patching and backup administration compared with self-hosting.

API ingress is public HTTPS and this starter has no application authentication. Key Vault uses its public endpoint with RBAC. Production exposure needs an access-control design and appropriate network restrictions. Validation does not check Azure capacity, regional SKU availability, permissions, connectivity or an actual rollout.

References: [Container App resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app), [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking), [Azure Storage state backend](https://developer.hashicorp.com/terraform/language/backend/azurerm).
