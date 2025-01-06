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
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: TCA Hybrid Analysis
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          mesh-config: "./path/to/mesh-configs.yaml"
          kube-config: ${{ secrets.KUBECONFIG }}
```

### Local-Only Mode

Use this mode for initial validation of configuration files without cluster access. 

> [!WARNING]  
> Since TCA analyze Istio runtime configuration, it needs following resources to be available as part of 
> mesh-config file: Istio mesh-config configmap, Istiod deployment resource and Istio secrets. 
> You will need to merge these resources with configurations that you want to apply. 


```yaml
name: Local Config Analysis
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: TCA Local Analysis
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          mesh-config: "./path/to/mesh-configs.yaml"   # Must contain Istio mesh configmap, Istiod deployment and secrets
          local-only: true
```

### Cluster Mode

For analyzing deployed configurations in your cluster:

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
      - uses: actions/checkout@v4
      
      - name: Run TCA Analysis
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          kube-config: ${{ secrets.KUBECONFIG }}
```

## Advanced Usage

Following is more complete example that

- combines all existing Istio config files in a repository
- uses TCA to analyze the combined config
- adds PR comment to show TCA output
- requires appropriate permissions for GITHUB_TOKEN to post comments. See GitHub's documentation on [defining token permissions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token#defining-access-for-the-github_token-permissions) for more details.

```yaml
name: Validate Istio Configs
permissions:
  pull-requests: write  # Required for commenting on PRs
on:
  pull_request:
    paths:
      - 'istio/**'
      - 'manifests/**'

jobs:
  validate-configs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # Collect and combine Istio configs
      - name: Collect Istio Configs
        run: |
          # Create directory for combined configs
          mkdir -p ./combined

          # Collect all Istio related YAMLs into single file
          {
            echo "# Combined Istio Configurations"
            echo "---"
            
            # Find and combine specific Istio API versions
            find . -type f -name "*.yaml" -o -name "*.yml" | \
            while read -r file; do
              # Only process files containing Istio API versions
              if grep -q "apiVersion: \(networking\|security\|telemetry\).istio.io" "$file"; then
                echo "# Source: $file"
                cat "$file"
                echo "---"
              fi
            done
          } > ./combined/mesh-configs.yaml
      
      # Run TCA analysis
      - name: Validate Istio Configs
        id: analyze
        uses: tetratelabs/tca-action@main
        with:
          tis-password: ${{ secrets.TIS_PASSWORD }}
          mesh-config: "./combined/mesh-configs.yaml"
          kube-config: ${{ secrets.KUBECONFIG }}

      # Add comment on PR with the analysis results
      - name: Comment on PR
        if: always()
        uses: thollander/actions-comment-pull-request@v3
        with:
          message: |
            ### Tetrate Config Analyzer Results
            ```
            ${{ steps.analyze.outputs.stdout }}
            ```
```

## Configuration Reference

### Input Parameters

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `tis-password` | Tetrate Istio Subscription (TIS) password for authentication | Yes | N/A |
| `local-only` | Analyze configuration files locally without connecting to a Kubernetes cluster | No | `false` |
| `mesh-config` | Path to the Istio service mesh configuration file (required when using local-only mode) | No | `""` |
| `kube-config` | Path to the Kubernetes config file for cluster analysis. Not used in local-only mode | No | `""` |
| `version` | TCA version to use (e.g. '1.2.3'). Use 'latest' for most recent version | No | `latest` |

## Support

For issues and feature requests related to this GitHub Action, please open an issue in the [tetratelabs/tca-action](https://github.com/tetratelabs/tca-action) repository.

For TCA product documentation and support, visit [Tetrate Documentation](https://docs.tetrate.io).
