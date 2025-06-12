# Pinot PR Reports

A simple web interface for visualizing Apache Pinot pull request (PR) reports. This site dynamically loads JSON files 
from the `data/` directory and displays them based on a selected time range.

**Live Demo**: [https://uoetianlezhang.github.io/pinot-pr-reports](https://uoetianlezhang.github.io/pinot-pr-reports)

> If you see a `404` for `manifest.json`, the deployment may be delayed or the `data/output/manifest.json` file wasn't generated.

## Test Locally

### 1. Install dependencies (run once)
```bash
npm ci
```

### 2. Run locally
```bash
npm run dev
```
This will generate `data/output/manifest.json` and serve the project at `localhost`.

## Build Instructions
To generate the `manifest.json`:
```bash
npm run build
```
This scans the `data/` directory and creates or updates `data/output/manifest.json` listing all `*.json` files.

## GitHub Actions Deployment
This site is automatically built and deployed on push to the `main` or via manual run in the GHA Actions tab.