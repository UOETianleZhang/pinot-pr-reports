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
This site is automatically built and deployed on push to the `main` or via manual run in the GitHub Actions tab.

## Backfilling PR Reports

Since this repo was created >10 years after the first commit to Apache Pinot, there are thousands of PRs that don't have reports reflected here. There's a Github Action called "Backfill Commit Comparison Generator" to help fix that issue. All the user needs to do is input the date range of the merged PRs they want reports for. (Note that both dates need to be in UTC and in ISO 8601, i.e. '1970-01-01T00:00:00Z'.)
