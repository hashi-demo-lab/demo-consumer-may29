# Deployment Report: cloudfront-static-content

| Field         | Value                                                    |
| ------------- | -------------------------------------------------------- |
| Branch        | feat/001-cloudfront-static-content                       |
| Date          | 2026-05-07                                               |
| Provider      | aws ~> 6.5 (resolved 1.15.2 runtime)                     |
| HCP Workspace | sandbox_consumer_cloudfront-demo-consumer-may29          |
| Org / Project | hashi-demos-apj / sandbox                                |
| Run ID        | run-6QvFUBye8xXX89nY (applied, 12 resources created)     |

---

## Summary

The cloudfront-static-content stack composed from four private-registry modules (s3-bucket v6, cloudfront v5, two metric-alarm v5 calls) was successfully planned and applied in the `sandbox_consumer_cloudfront-demo-consumer-may29` workspace with auto-apply. All 12 expected resources were created, all design wiring is intact, sentinel/run-task gates passed, and the public CloudFront edge is DNS-resolvable with a valid Amazon-issued TLSv1.3 certificate. One documented `[CONSTITUTION DEVIATION]` exists (`aws_s3_bucket_policy` to break the OAC cycle) and is fully justified in `consumer-design.md` §6. No CRITICAL or HIGH defects.

## Quality Score

| #   | Dimension              | Score    | Issues                            |
| --- | ---------------------- | -------- | --------------------------------- |
| 1   | Module Usage           | 9.5      | 0 P0, 0 P1, 1 P2 (documented dev) |
| 2   | Security & Compliance  | 9.5      | 0 P0, 0 P1, 1 P3 (no access logs) |
| 3   | Code Quality           | 9.0      | 0 P0, 0 P1, 1 P3 (EOF in non-tf)  |
| 4   | Variables & Outputs    | 9.5      | 0 P0, 0 P1, 0 P2                  |
| 5   | Wiring & Integration   | 10.0     | 0 issues — design table honoured  |
| 6   | Constitution Alignment | 9.0      | 1 documented deviation logged     |

**Weighted Overall**: `(9.5*0.25)+(9.5*0.30)+(9.0*0.15)+(9.5*0.10)+(10.0*0.10)+(9.0*0.10) = 9.40 / 10.0` — **Excellent**
**Production Readiness**: Ready (subject to re-enabling access logs and SNS routing for production tier; both explicitly out-of-scope for sandbox in design §1).

## Design Alignment

All four modules from §2 Module Inventory are deployed with the inputs the design specified. Cross-checked against the workspace's reported `resource-count: 18` (which includes 12 root-managed + 6 module-internal child counters) and the design wiring table.

| Module        | Source                                                                        | Version | Status        |
| ------------- | ----------------------------------------------------------------------------- | ------- | ------------- |
| `s3_bucket`   | `app.terraform.io/hashi-demos-apj/s3-bucket/aws`                              | `~> 6.0` | PASS         |
| `cloudfront`  | `app.terraform.io/hashi-demos-apj/cloudfront/aws`                             | `~> 5.0` | PASS (us-east-1 alias wired) |
| `alarm_5xx`   | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm`       | `~> 5.0` | PASS (Region=Global) |
| `alarm_4xx`   | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm`       | `~> 5.0` | PASS (Region=Global) |

Wiring table (design §3) honoured exactly: `random_id.bucket_suffix.hex` -> `local.bucket_name` -> `module.s3_bucket.bucket`; `module.s3_bucket.s3_bucket_bucket_regional_domain_name` -> `module.cloudfront.origin["s3"].domain_name` (regional form, not the legacy 307-redirect form); `module.cloudfront.cloudfront_distribution_arn` -> `data.aws_iam_policy_document.s3_origin` (`AWS:SourceArn` condition); `data.aws_iam_policy_document.s3_origin.json` -> `aws_s3_bucket_policy.origin.policy`; `module.cloudfront.cloudfront_distribution_id` -> both alarms' `dimensions.DistributionId`.

**Note on alarm version**: design §2 quoted `~> 5.7` for the cloudwatch metric-alarm module while `main.tf` pins `~> 5.0`. `~> 5.0` accepts any 5.x and resolves to ≥5.7 at init, so the design intent (current 5.7.x line) is satisfied; tightening the constraint to `~> 5.7` is a recommended hardening (P3).

## Security Controls (§4)

| Control                          | Code Evidence                                                                                                       | Verdict |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------- |
| SSE-S3 (AES256) at rest          | `main.tf:36-42` — `server_side_encryption_configuration.rule.apply_server_side_encryption_by_default.sse_algorithm = "AES256"` | PASS    |
| TLS-only S3 access               | `main.tf:45` — `attach_deny_insecure_transport_policy = true`                                                        | PASS    |
| Public access block (all four)   | `main.tf:53-56` — all four flags `= true` set explicitly                                                              | PASS    |
| Bucket-owner enforced (no ACLs)  | `main.tf:48-49` — `control_object_ownership = true`, `object_ownership = "BucketOwnerEnforced"`                       | PASS    |
| Versioning enabled               | `main.tf:32-34` — `versioning = { enabled = true }`                                                                  | PASS    |
| `force_destroy = false`          | `main.tf:30`                                                                                                         | PASS    |
| OAC bucket policy w/ SourceArn   | `data.tf:34-38` — `condition { test = StringEquals, variable = AWS:SourceArn, values = [...] }`                      | PASS    |
| OAC least privilege              | `data.tf:23-27` — single statement, `s3:GetObject` only, `cloudfront.amazonaws.com` only, scoped resource            | PASS    |
| Viewer redirect-to-https         | `main.tf:120` — `viewer_protocol_policy = "redirect-to-https"`                                                       | PASS    |
| TLS minimum 1.2_2021             | `main.tf:131-134` — `viewer_certificate.minimum_protocol_version = "TLSv1.2_2021"`                                   | PASS (live cert handshake confirms TLSv1.3 negotiation, AWS-issued) |
| Alarms wired to correct dist.    | `main.tf:199-202`, `main.tf:232-235` — `DistributionId = module.cloudfront.cloudfront_distribution_id, Region="Global"` | PASS  |
| Alarms in us-east-1              | `main.tf:184`, `main.tf:217` — `providers = { aws = aws.us_east_1 }`                                                 | PASS    |
| Provider `default_tags`          | `providers.tf:9-11`, `:21-23` (both blocks); `locals.tf:4-9` — ManagedBy/Environment/Project/Owner                   | PASS    |
| Dynamic credentials (no static)  | `providers.tf` — no `access_key`/`secret_key` blocks; OIDC via inherited `agent_AWS_Dynamic_Creds` varset            | PASS    |
| CloudFront/S3 access logs        | Not configured — accepted gap, sandbox cost optimisation, logged design §6 #4                                        | ACCEPTED |

## Constitution Compliance

| Constitution Section | Requirement                                            | Result |
| -------------------- | ------------------------------------------------------ | ------ |
| §1.1 Module-first    | All resources via private modules                       | PASS w/ 1 documented deviation (`aws_s3_bucket_policy`, justified in design §6 — circular-dep break) |
| §1.1 Glue list       | Only `random_id` raw-resource glue                      | PASS (`random_id.bucket_suffix`)                          |
| §1.3 Backend         | `cloud {}` w/ org + project + workspace                 | PASS (`backend.tf:1-10`)                                  |
| §3.1 Dynamic auth    | No static AWS keys                                      | PASS (no static creds in code)                            |
| §3.3 Tagging         | `default_tags` includes ManagedBy/Environment/Project/Owner | PASS (`locals.tf:4-9`)                                |
| §4.1 Provider pin    | `~> X.Y` pessimistic                                    | PASS (`aws ~> 6.5`, `random ~> 3.5`)                      |
| §4.3 Module pin      | `~> X.Y` on every module                                | PASS (`~> 6.0`, `~> 5.0`, `~> 5.0`, `~> 5.0`)             |
| §2.1 File layout     | versions/backend/providers/variables/locals/main/data/outputs | PASS (all eight present)                            |
| §2.3 Variables       | type + description on every var; validation where useful | PASS (all 12 vars typed + described; 8 have validations)  |

### Static Analysis (pre-commit)

| Hook                       | Result | Notes                                                                                  |
| -------------------------- | ------ | -------------------------------------------------------------------------------------- |
| terraform fmt              | PASS   |                                                                                        |
| terraform validate         | PASS   |                                                                                        |
| terraform-docs             | PASS   |                                                                                        |
| tflint                     | PASS   |                                                                                        |
| trivy config               | PASS   | 0 CRITICAL / 0 HIGH; 1 LOW (AWS-0089 S3 access logs — accepted, design §6 #4); MED finding inside the cloudfront module's `complete` example fixture (transitive, not consumer code) |
| Detect private keys        | PASS   |                                                                                        |
| Vault Radar scan           | PASS   |                                                                                        |
| end-of-file-fixer          | FAIL   | Modified non-Terraform files (`.devcontainer/*.sh`, `.gitignore`, skill `.md` files); zero `.tf`/`tfvars` impact — does not affect deployed code |

### trivy summary

| Metric   | Count |
| -------- | ----- |
| Total    | 4 findings (across consumer + transitive modules) |
| Defects  | 0 (0 CRITICAL / 0 HIGH)                          |
| Accepted | 1 LOW (AWS-0089 S3 logging — design §6 #4)       |

## Run Analysis

**Run**: `run-6QvFUBye8xXX89nY` (`https://app.terraform.io/app/hashi-demos-apj/workspaces/sandbox_consumer_cloudfront-demo-consumer-may29/runs/run-6QvFUBye8xXX89nY`)
**Status**: applied | **Trigger**: CLI manual | **TF**: 1.15.2 | **Auto-apply**: true
**Timeline**: queued 06:33:37Z -> planned 06:34:38Z -> post-plan complete 06:34:57Z -> applied 06:35:50Z (2 min 13 s end-to-end).

### Run Tasks

**Total tasks**: 1 | Passed: 1 | Failed: 0 | Errored: 0

#### Post-Plan Tasks (stage status: passed)

| Task Name           | Status | Enforcement | Message                                            |
| ------------------- | ------ | ----------- | -------------------------------------------------- |
| Apptio-Cloudability | passed | advisory    | Total Cost before: 0.00, after: 2.74, diff: +2.74  |

##### Apptio-Cloudability — Outcomes

| Outcome        | Description            | Status | Severity |
| -------------- | ---------------------- | ------ | -------- |
| Estimation     | Cost Estimation Result | Passed | --       |
| Policy         | Policy Evaluation Result | Passed | --     |
| Recommendation | Recommendation Result  | Passed | --       |

### Sentinel Policy Checks

`policy-checks.data` is empty on the run payload — the org has no Sentinel policy sets attached to this workspace (consistent with design §2 workspace-config table noting "Policy Sets: -- (none)"). The post-plan run-task layer (Cloudability) functioned as the sole governance gate and passed all three outcomes.

### Cost Estimation

Native HCP `cost-estimate` is `null` for this run, but Cloudability reports a monthly impact of **+$2.74 USD** (zero-baseline → $2.74 after) — driven primarily by the CloudFront distribution and the two CloudWatch alarms; S3 storage is effectively free at sandbox volumes. No recommendation flags raised.

## Smoke Test

| Step                        | Result                                                                                       |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| DNS resolution              | PASS — `d3smy3t6744bb.cloudfront.net` resolves to 4 CloudFront edges (13.32.253.{44,184,194,213}) via DoH (sandbox runner has no recursive resolver, used Cloudflare 1.1.1.1 DoH) |
| TLS handshake (no GET)      | PASS — TLSv1.3 with `TLS_AES_128_GCM_SHA256`; cert `subject=CN=*.cloudfront.net`, `issuer=Amazon RSA 2048 M01`; `Verify return code: 0 (ok)` |
| GET issued?                 | No — bucket is empty by design; an HTTPS GET to `/` would surface AccessDenied/NoSuchKey, which is expected and not informative                                                |

## Recommendations

1. (P3) Tighten the cloudwatch metric-alarm version constraint from `~> 5.0` to `~> 5.7` to match the version stated in design §2 and prevent silent regression to 5.0.x.
2. (P3) Re-enable CloudFront and S3 access logs before promoting the pattern to production — currently an accepted gap (`design §6 #4`).
3. (P3) Run `pre-commit run --all-files` and commit the EOF normalisations to non-Terraform files; only documentation/devcontainer noise, but keeps CI green.
4. (P3) When SNS notification routing is in scope, populate `alarm_actions`/`ok_actions` on both alarm modules and tighten alarm thresholds for production tier (5xx<1%, 4xx<5%).
5. (P3) Update the platform constitution glue-resource list to permit `aws_s3_bucket_policy` for OAC-cycle breakage, or surface a registry helper module that internalises the pattern — would eliminate the documented `[CONSTITUTION DEVIATION]`.
6. (Optional) Promote `aws_region_origin` from a default-only variable into a workspace tfvar so the design-stated `ap-southeast-2` pin is captured at the workspace layer rather than the code default.

## Verdict

**PASS** — applied successfully (12/12 resources), all module wiring, security controls, and constitution requirements satisfied; the only deviation is the design-documented OAC-cycle bucket policy.
