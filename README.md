# Tetrate Config Analyzer (TCA) GitHub Action

[The Tetrate Config Analyzer (TCA)](https://docs.tetrate.io/istio-subscription/tools/tca/) Action is a powerful GitHub Action that helps you validate and analyze Istio service mesh configurations using TCA (Tetrate Config Analyzer). This tool supports both cluster-based and local file-based configuration analysis, making it versatile for various deployment scenarios.

## Overview
TCA GitHub Action enables you to:

- Validate Istio configurations before deployment
- Detect potential issues in your service mesh setup
- Ensure compliance with best practices
- Automate configuration analysis in your CI/CD pipeline

## Prerequisites

Before using the TCA GitHub Action, ensure you have:
- Valid [Tetrate Istio Subscription (TIS)](https://docs.tetrate.io/istio-subscription/introduction/) credentials
- Access to a Kubernetes cluster with Istio installed
- Istio configuration files

## Operating Modes

### Hybrid Mode

Hybrid mode analyze configuration that you want to apply with cluster context:

```yaml
name: Hybrid Config Analysis

on:
  push:
    branches:
      - "main"
  pull_request:
    branches:
      - "main"

jobs:
  analyze-configs:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Validate Istio Configs
        id: tca
        uses: aegisworks/istio-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          mesh-config: "./invalid.yaml"
          kube-config: ${{ secrets.KUBECONFIG }}

      - name: Comment on PR
        uses: thollander/actions-comment-pull-request@v3
        with:
          file-path: ${{ steps.tca.outputs.result-file }}

      - name: Optionally Fail if there are errors
        run: |
          if [ ${{ env.error-count }} -gt 0 ]; then
            exit 1
          fi
```

### Local-Only Mode

Use this mode for initial validation of configuration files without cluster access. 

> [!WARNING]  
> Since TCA analyze Istio runtime configuration, it needs following resources to be available as part of 
> mesh-config file: Istio mesh-config configmap, Istiod deployment resource and Istio secrets. 
> You will need to merge these resources with configurations that you want to apply. 


```yaml
name: Local Config Analysis

on:
  push:
    branches:
      - "main"
  pull_request:
    branches:
      - "main"

jobs:
  analyze-configs:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: TCA Local Analysis
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          mesh-config: "./path/to/mesh-configs.yaml"   # Must contain Istio mesh configmap, Istiod deployment and secrets
          local-only: true
```

### Cluster Mode

For periodically analyzing deployed configurations in your cluster:

```yaml
name: Cluster Analysis
on:
  # Scheduled cluster scan
  schedule:
    # Run every day at 00:00 UTC
    - cron: '0 0 * * *'

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Run TCA Analysis
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          kube-config: ${{ secrets.KUBECONFIG }}
```

## Configuration Reference

### Input Parameters

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `tis-password` | Tetrate Istio Subscription (TIS) password for authentication | Yes | N/A |
| `local-only` | Analyze configuration files locally without connecting to a Kubernetes cluster | No | `false` |
| `mesh-config` | Path to the Istio service mesh configuration file (required when using local-only mode) | No | `""` |
| `kube-config` | Path to the Kubernetes config file for cluster analysis. Not used in local-only mode | No | `""` |
| `version` | TCA version to use (e.g. '1.1.0'). Use 'latest' for most recent version | No | `v1.2.0` |

### Output Parameters

| Input | Description | Value |
|-------|-------------|-------|
| `result-file` | Path of TCA analysis output result. Use markdown format | `${{ github.workspace }}/tca-output.txt` |

## Support

For issues and feature requests related to this GitHub Action, please open an issue in the [tetratelabs/tca-action](https://github.com/tetratelabs/tca-action) repository.

For TCA product documentation and support, visit [Tetrate Documentation](https://docs.tetrate.io).
