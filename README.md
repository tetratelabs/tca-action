# TCA Action

A GitHub Action for running TCA(Tetrate Config Analyzer) on Linux and macOS virtual environments.

## Usage

### Quickstart

```yaml
name: Build and Test
on:
  push:
    branches:
      - "main"
  pull_request:
    branches:
      - "main"
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          path: tca
          clean: true

      - name: Run TCA
        uses: tetratelabs/tca-action
        with:
          tisToken: ${{ secrets.TIS_PASS }}
          meshConfigFile: ./manifest.yaml
          localOnly: true
```

### Customizing

The following are optional as `step.with` keys

| Name             | Type    | Required | Description                                           |
| ---------------- | ------- | -------- | ----------------------------------------------------- |
| `tisToken`       | String  | `true`   | TIS password                                          |
| `localOnly`      | Boolean | `false`  | If true, TCA will not try to connect a remote cluster |
| `meshConfigFile` | String  | `false`  | Path to the mesh configuration file                   |
| `kubeConfig`     | String  | `false`  | Path to the kubeconfig file                           |
| `tcaVersion`     | String  | `false`  | The version of TCA binary                             |
