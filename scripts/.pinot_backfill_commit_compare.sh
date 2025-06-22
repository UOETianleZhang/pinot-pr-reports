#!/usr/bin/env bash
# scripts/.pinot_backfill_commit_compare.sh

set -euo pipefail

# 0) Ensure required tools are present
for cmd in gh mvn node; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: '$cmd' not found in PATH." >&2
    exit 1
  }
done

usage() {
  cat <<EOF
Usage: $(basename "$0") --start <ISO8601> --end <ISO8601> [--outdir <path>]

Options:
  -s, --start     Start of interval (UTC ISO 8601)
  -e, --end       End of interval   (UTC ISO 8601)
  -o, --outdir    Base output dir (default: data)
  -h, --help      Show this help and exit

Environment:
  DRY_RUN=true    Skip builds & diffs; just print which PRs would be processed.
EOF
  exit 1
}

# --- parse flags ---
START_DATE=""
END_DATE=""
OUTDIR="data"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--start)     START_DATE="$2"; shift 2;;
    -e|--end)       END_DATE="$2";   shift 2;;
    -o|--outdir)    OUTDIR="$2";     shift 2;;
    -h|--help)      usage;;
    *) echo "Unknown option: $1" >&2; usage;;
  esac
done

if [[ -z "$START_DATE" || -z "$END_DATE" ]]; then
  echo "Error: both --start and --end are required" >&2
  usage
fi

echo "➡️  Backfilling from $START_DATE to $END_DATE into ‘$OUTDIR’..."

# --- vars ---
REPO_URL="https://github.com/apache/pinot.git"
REPO_DIR="pinot"
JAPICMP_VER="0.23.1"
JAPICMP_JAR="japicmp.jar"
JAR_NEW="commit_jars_new"
JAR_OLD="commit_jars_old"
JAPICMP_OUT="$OUTDIR/japicmp"
JSON_OUT="$OUTDIR/output"

# 1) Fresh clone
rm -rf "$REPO_DIR"
git clone --branch master "$REPO_URL" "$REPO_DIR"

# 2) Collect SHAs
PR_SHAS=()
while IFS= read -r sha; do
  PR_SHAS+=("$sha")
done < <(
  git -C "$REPO_DIR" log \
    --since="$START_DATE" --until="$END_DATE" \
    --reverse --format='%H'
)

if (( ${#PR_SHAS[@]} == 0 )); then
  echo "ℹ️  No commits found."
  exit 0
fi

# 3) Baseline & version
pushd "$REPO_DIR" >/dev/null
BASELINE_SHA=$(git rev-parse "${PR_SHAS[0]}^")
VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | tr -d '%')
popd >/dev/null

# 4) Prepare temp dirs & outputs
rm -rf "$JAR_NEW" "$JAR_OLD"
mkdir -p "$JAR_NEW" "$JAR_OLD"
mkdir -p "$JAPICMP_OUT" "$JSON_OUT"

# 5) Japicmp jar
if [[ ! -f "$JAPICMP_JAR" ]]; then
  curl -fSL -o "$JAPICMP_JAR" \
    "https://repo1.maven.org/maven2/com/github/siom79/japicmp/japicmp/${JAPICMP_VER}/japicmp-${JAPICMP_VER}-jar-with-dependencies.jar"
fi

# 6) Loop PRs
for SHA in "${PR_SHAS[@]}"; do
  PR_NUM=$(gh api repos/apache/pinot/commits/"$SHA"/pulls \
    -H "Accept: application/vnd.github.groot-preview+json" \
    --jq '.[0].number')

  # DRY RUN?
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "[DRY-RUN] PR #${PR_NUM}: baseline $BASELINE_SHA → $SHA"
    BASELINE_SHA="$SHA"
    continue
  fi

  # Skip if already done
  if [[ -f "$JAPICMP_OUT/pr-${PR_NUM}.json" ]]; then
    echo "⚡ #${PR_NUM} exists; skipping."
    BASELINE_SHA="$SHA"
    continue
  fi

  echo "▶ PR #${PR_NUM} (commit $SHA)"

  # a) Build baseline (resilient to failure)
  pushd "$REPO_DIR" >/dev/null
  git checkout "$BASELINE_SHA"
  if ! mvn clean install -T1C -DskipTests -q; then
    echo "⚠️ Maven build failed at baseline $BASELINE_SHA for PR #${PR_NUM}, skipping this PR."
    popd >/dev/null
    BASELINE_SHA="$SHA"
    continue
  fi
  popd >/dev/null
  find "$REPO_DIR" -name "*${VERSION}.jar" -exec mv {} "$JAR_NEW/" \;

  # b) Build current (resilient to failure)
  pushd "$REPO_DIR" >/dev/null
  git checkout "$SHA"
  if ! mvn clean install -T1C -DskipTests -q; then
    echo "⚠️ Maven build failed at current commit $SHA for PR #${PR_NUM}, skipping this PR."
    popd >/dev/null
    BASELINE_SHA="$SHA"
    continue
  fi
  popd >/dev/null
  find "$REPO_DIR" -name "*${VERSION}.jar" -exec mv {} "$JAR_OLD/" \;

  # sanity-check
  if [[ -z "$(ls -A "$JAR_NEW")" ]]; then
    echo "❌ No new jars; skipping PR #${PR_NUM}."
    BASELINE_SHA="$SHA"
    continue
  fi
  if [[ -z "$(ls -A "$JAR_OLD")" ]]; then
    echo "❌ No old jars; skipping PR #${PR_NUM}."
    BASELINE_SHA="$SHA"
    continue
  fi

  # c) Run japicmp
  TXT="pr-${PR_NUM}.txt"
  : > "$TXT"
  for NEWJ in "$JAR_NEW"/*.jar; do
    NAME=$(basename "$NEWJ")
    OLDJ="$JAR_OLD/$NAME"
    if [[ ! -f "$OLDJ" ]]; then
      echo "Missing in previous PR: $NAME" >> "$TXT"
      echo >> "$TXT"
      continue
    fi
    java -jar "$JAPICMP_JAR" \
      --old "$OLDJ" --new "$NEWJ" \
      -a private --no-annotations --ignore-missing-classes --only-modified \
      >> "$TXT"
  done

  # d) Parse to JSON
  METADATA=$(gh pr view "$PR_NUM" -R apache/pinot \
    --json title,number,mergedAt,files,url \
    --jq '.files |= [.[]|.path]')
  node scripts/parse_japicmp.js \
    --input "$TXT" --metadata "$METADATA" \
    --output "pr-${PR_NUM}.json"

  mv "$TXT"                "$JAPICMP_OUT/"
  mv "pr-${PR_NUM}.json"   "$JSON_OUT/"

  # e) Rotate
  rm -rf "${JAR_NEW:?}"/*
  mv "$JAR_OLD"/* "$JAR_NEW"/
  BASELINE_SHA="$SHA"
done

# 7) Cleanup
rm -rf "$REPO_DIR" "$JAR_NEW" "$JAR_OLD"

echo "✅ Backfill complete."