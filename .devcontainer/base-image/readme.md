# Base Image: terraform-ai-tools

Multi-architecture devcontainer base image for Terraform development with AI tooling support.

**Platforms:** `linux/amd64`, `linux/arm64`

## Included Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | 25.7.0 (slim) | Runtime |
| Go | 1.24 | Provider development |
| Terraform | 1.14.6 | Infrastructure provisioning |
| terraform-docs | 0.21.0 | Documentation generation |
| TFLint | 0.60.0 | Linting (AWS/Azure/GCP rulesets) |
| Infracost | 0.10.43 | Cost estimation |
| Checkov | 3.2.504 | Security scanning |
| Vault Radar | 0.43.0 | Secret detection |
| pre-commit | via uv | Git hooks |
| golangci-lint | 2.10.1 | Go linting |
| git-delta | 0.18.2 | Diff viewer |
| GitHub CLI (gh) | system | GitHub operations |
| uv | latest | Python package management |

## Building

### Prerequisites

- Docker with buildx enabled
- A buildx builder with multi-platform support (e.g., `docker-container` driver)

### Set up builder (one-time)

```bash
docker buildx create --name multiplatform --driver docker-container --bootstrap
```

### Build and push (multi-arch)

```bash
cd .devcontainer/base-image

docker buildx use multiplatform

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <your-registry>/terraform-ai-tools:latest \
  --push .
```

### Build locally (single arch, no push)

```bash
cd .devcontainer/base-image

docker buildx build \
  --platform linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
  -t <your-registry>/terraform-ai-tools:latest \
  --load .
```
