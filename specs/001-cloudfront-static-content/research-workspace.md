## Research: How should the HCP Terraform workspace be configured for this consumer deployment?

### Decision

Create the workspace `sandbox_consumer_cloudfront-demo-consumer-may29` inside the existing `sandbox` project (`prj-QueMgU3LXgV2Ag7s`) in the `hashi-demos-apj` organization with `execution_mode = "remote"`, `auto_apply = true`, `terraform_version = "1.14.8"`, and no working directory. The variable set `agent_AWS_Dynamic_Creds` (`varset-9BtXAvxByVGEnHWV`) is already attached at the project scope and will be inherited automatically — no explicit workspace attachment is required. AWS provider aliases for `us-east-1` (CloudFront) and `ap-southeast-2` (S3) both authenticate via the same OIDC role assumption from the inherited variable set; no per-region provider blocks need additional credential configuration.

### Modules Identified

This research covers HCP Terraform workspace configuration only — no Terraform modules are sourced. The deliverable is the `cloud {}` block, workspace settings, and variable-set/policy attachments.

#### Recommended `cloud {}` Block (in `versions.tf`)

```hcl
terraform {
  required_version = ">= 1.14.0"

  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name    = "sandbox_consumer_cloudfront-demo-consumer-may29"
      project = "sandbox"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

Notes on the `cloud {}` block:
- `organization` and `workspaces.name` are required.
- `workspaces.project` is supported when the workspace is created via CLI-driven workflow and ensures the workspace is provisioned in the correct project scope on first `terraform init`. If the workspace is pre-created via the API/UI, this attribute can still be set but is ignored on subsequent inits.
- Do **not** set both `workspaces.name` and `workspaces.tags` — they are mutually exclusive.
- No `hostname` needed — defaults to `app.terraform.io` (HCP Terraform).

#### Workspace Settings

| Setting | Value | Source / Justification |
|---------|-------|------------------------|
| Organization | `hashi-demos-apj` | Provided in research question |
| Project | `sandbox` (`prj-QueMgU3LXgV2Ag7s`) | Provided; default-execution-mode = `remote` |
| Workspace name | `sandbox_consumer_cloudfront-demo-consumer-may29` | Provided; matches `sandbox_consumer_*` naming convention seen on existing workspaces (e.g., `sandbox_consumer_serverlessdemo-rsa`, `sandbox_consumer_serverlessterraform-agentic-workflows-demo06`) |
| Execution mode | `remote` | Project default; all 5 sibling workspaces use `remote` |
| Auto apply | `true` | Sandbox / development tier with minimal cost — auto-apply preferred per requirements. NOTE: existing siblings have `auto-apply = false`; setting this workspace to `true` is a deliberate deviation justified by the sandbox-demo nature of this consumer deployment |
| Terraform version | `1.14.8` | Latest stable in the 1.14.x line; matches `sandbox_consumer_serverlessdemo-rsa` (most recently created sibling). Org default-execution-mode does not pin a TF version. |
| Working directory | `null` (none) | All sibling workspaces have no working directory — repo root contains the root module |
| Speculative plans | `true` (default) | Enables PR plans for VCS-connected mode |
| Global remote state | `false` | No cross-workspace state sharing required |
| Assessments | `false` (default) | Sandbox tier — drift detection not required |
| Tags | `["sandbox", "consumer", "cloudfront", "demo"]` (recommended) | Aids workspace discovery; not required by org policy |

#### Variable Set Attachment

| Variable Set | ID | Variables | Attachment |
|--------------|-----|-----------|------------|
| `agent_AWS_Dynamic_Creds` | `varset-9BtXAvxByVGEnHWV` | `TFC_AWS_PROVIDER_AUTH=true`, `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::855831148133:role/tfstacks-role`, `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE=aws.workload.identity` | **Already attached to project `prj-QueMgU3LXgV2Ag7s` (sandbox)** — inherited automatically by any workspace created in the project. No workspace-level attachment required. |

This variable set provisions HCP Terraform's native AWS dynamic-credentials workflow (OIDC). The workspace will receive a short-lived JWT signed by HCP Terraform, which the AWS provider exchanges via `sts:AssumeRoleWithWebIdentity` against the `tfstacks-role` in account `855831148133`. Both AWS provider aliases (`us-east-1` and `ap-southeast-2`) automatically pick up these env vars; no additional region-scoped credentials are needed. The variable set has `priority = true`, so its values override workspace-level vars of the same name if any conflict arises.

#### Policy Sets

The `hashi-demos-apj` organization has **zero policy sets** configured (`/api/v2/organizations/hashi-demos-apj/policy-sets` returns `total-count: 0`). No Sentinel or OPA enforcement applies. No action required.

#### Glue Resources Needed

None for the workspace itself. The workspace is provisioned out-of-band (via `terraform login` + `terraform init`, or via the HCP Terraform UI / a separate management workspace). The consumer deployment's `cloud {}` block consumes the workspace; it does not create it.

#### Wiring Considerations

- **Cross-region providers**: With OIDC dynamic credentials, all AWS provider aliases share the same assumed-role identity. Define the second alias purely with `region = "us-east-1"` and `alias = "us_east_1"`; no separate `assume_role` block needed since `TFC_AWS_RUN_ROLE_ARN` is set globally for the run.

  ```hcl
  provider "aws" {
    region = "ap-southeast-2"  # default for S3 origin
  }

  provider "aws" {
    alias  = "us_east_1"
    region = "us-east-1"  # required for CloudFront-attached ACM certs and CloudFront itself
  }
  ```

- **CloudFront region constraint**: CloudFront is a global service but is managed via the `us-east-1` regional API endpoint. ACM certificates referenced by CloudFront distributions **must** also reside in `us-east-1`. The `aws.us_east_1` alias must be passed to any module call that creates a CloudFront distribution or its ACM cert.

### Rationale

1. **Variable set is project-scoped, not workspace-scoped**: Querying `/api/v2/organizations/hashi-demos-apj/varsets` shows only one variable set (`agent_AWS_Dynamic_Creds`), and its `relationships.projects` includes `prj-QueMgU3LXgV2Ag7s` (sandbox). HCP Terraform inherits project-scoped variable sets to all workspaces in the project. This is confirmed by `var-count: 3` and `priority: true`.

2. **OIDC vs static keys**: The three variables (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`, `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE`) are exactly the contract HCP Terraform's [native AWS dynamic credentials feature](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration) requires. No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are present, confirming the org has standardized on OIDC.

3. **Naming convention**: Five workspaces in the sandbox project follow either `sandbox_consumer_<purpose>` or `sandbox_<other>` patterns. The provided name `sandbox_consumer_cloudfront-demo-consumer-may29` cleanly fits the `sandbox_consumer_*` family.

4. **Terraform version**: The most recently created sibling (`sandbox_consumer_serverlessdemo-rsa`, created 2026-03-26) uses `1.14.8`. The latest stable is `1.15.2`, but matching the established sandbox baseline reduces variance and HCP Terraform supports `1.14.8` natively. The `cloud {}` block uses `required_version = ">= 1.14.0"` to remain forward-compatible while pinning the workspace to `1.14.8`.

5. **Auto-apply deviation**: Sibling sandbox workspaces have `auto-apply = false`. The research question explicitly asks for `auto_apply` because of the sandbox/demo tier. Setting this to `true` is documented as an intentional deviation; reviewers can override at workspace creation time if they prefer manual confirmation.

6. **No policy sets to attach**: API returned zero policy sets at the org level, eliminating any Sentinel/OPA decision.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Attach `agent_AWS_Dynamic_Creds` directly to the workspace | Redundant — already attached at the project level. Would create duplicate inheritance and confuse future readers about scope of truth. |
| Use static AWS access keys via workspace variables | Org has standardized on OIDC dynamic credentials; static keys violate the explicit "no static keys" requirement. |
| Per-region role assumption via `assume_role` blocks in each provider alias | Unnecessary — `TFC_AWS_RUN_ROLE_ARN` env var is honored by the AWS provider regardless of region. Adding `assume_role` would either duplicate the role ARN or override it. |
| Use `workspaces.tags = ["sandbox", "consumer"]` instead of `workspaces.name` | Tag-based selection creates a multi-workspace configuration; this is a single-workspace deployment. `name` is the correct selector. |
| `terraform_version = "1.15.2"` (latest) | Diverges from the sandbox project baseline (`1.14.8`). Latest minor versions sometimes introduce provider-compat surprises; matching the most recent sibling is lower-risk for a demo. |
| Create a new `sandbox_AWS_Dynamic_Creds` variable set | The existing `agent_AWS_Dynamic_Creds` already serves the sandbox project. Creating a duplicate would diverge the AWS role/audience config across workspaces with no benefit. |
| Pin `terraform_version` exactly to `1.14.8` AND set `required_version = "= 1.14.8"` in code | Over-constrains. Workspace pin is sufficient; root-module `required_version` should use `>=` to allow forward upgrades. |
| Attach a Sentinel/OPA policy set | None exist in the org; nothing to attach. |

### Sources

- HCP Terraform organization API: `GET /api/v2/organizations/hashi-demos-apj` (default-execution-mode = remote, plan = premium_internal)
- Variable sets API: `GET /api/v2/organizations/hashi-demos-apj/varsets` (1 result: `agent_AWS_Dynamic_Creds` / `varset-9BtXAvxByVGEnHWV`, project-scoped, priority)
- Variable set vars: `GET /api/v2/varsets/varset-9BtXAvxByVGEnHWV/relationships/vars` (3 env vars implementing AWS OIDC contract)
- Projects API: `GET /api/v2/organizations/hashi-demos-apj/projects` (1 project: `sandbox` / `prj-QueMgU3LXgV2Ag7s`, 5 workspaces, default-execution-mode = remote)
- Sibling workspace: `GET /api/v2/workspaces/ws-J4BjgLWuPSxHsyWM` (`sandbox_consumer_serverlessdemo-rsa`, TF 1.14.8, remote, auto-apply false)
- Policy sets API: `GET /api/v2/organizations/hashi-demos-apj/policy-sets` (total-count: 0)
- Target workspace existence check: `GET /api/v2/organizations/hashi-demos-apj/workspaces/sandbox_consumer_cloudfront-demo-consumer-may29` returns 404 — workspace must be created.
- HashiCorp docs: [HCP Terraform AWS dynamic credentials configuration](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- HashiCorp docs: [`cloud` block reference](https://developer.hashicorp.com/terraform/language/settings/terraform-cloud)
- HashiCorp Releases API: latest Terraform = `1.15.2`
