#!/bin/bash

# Get count of commits since beginning of last workflow run. 
# Each workflow besides the very first one will look at all commits between the start time of the previous workflow
# and the start time of this workflow.
# If there are no commits within this timeframe, exit the script.
echo "$1"
commitcount=$(gh api repos/apache/pinot/commits --jq ".[] | select(.commit.committer.date >= \"$1\")" | wc -l)
if [[ commitcount -eq 0 ]]; then
  echo "There have been no commits since those processed by the last run of this workflow."
  exit 0
fi

# need # of commits + 1 to get the "old commit" for the earliest new commit
git clone --branch master --depth $((commitcount+1)) https://github.com/apache/pinot.git
cd pinot || exit
version="$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | tr -d "%")" # there's a % at the end for some reason
log="$(git log --pretty=format:"%H" | tr "\n" " ")"
IFS=' ' read -r -a hashlist <<< "$log"
cd ..
echo "commits being processed:" "${hashlist[*]}"

# make temp directories, download japicmp
mkdir commit_jars_old
mkdir commit_jars_new
if [ ! -e japicmp.jar ]; then
  JAPICMP_VER=0.23.1
  curl -fSL \
  -o japicmp.jar \
  "https://repo1.maven.org/maven2/com/github/siom79/japicmp/japicmp/${JAPICMP_VER}/japicmp-${JAPICMP_VER}-jar-with-dependencies.jar"
  if [ ! -f japicmp.jar ]; then
    echo "Error: Failed to download japicmp.jar."
    exit 1
  fi
fi

# get japicmp output for all commits
arrlen=${#hashlist[@]}
for i in $( seq 1 "$((arrlen - 1))" ); do
  latest_pr="$(gh api repos/apache/pinot/commits/"${hashlist[$((i-1))]}"/pulls \
          -H "Accept: application/vnd.github.groot-preview+json" | jq '.[0].number')" # corresponding PR number
  if [[ -e data/japicmp/pr-"$latest_pr".txt ]]; then
    echo "The change report for this PR already exists. The workflow will continue and just skip the process for this one."
    continue
  fi
  # we're only running mvn clean install twice for a PR at the beginning
  # since afterwards, we'll always have one of the two sets of jars downloaded already
  if [[ $i -eq 1 ]]; then
    cd pinot || exit
    git checkout "${hashlist[$((i-1))]}"
    mvn clean install -DskipTests -q
    echo "mvn clean #""$((i-1))"" done"
    paths="$(find . -type f -name "*${version}.jar" -print | tr "\n" " ")" # get all module jars made by mvn clean install
    IFS=' ' read -r -a namelist <<< "$paths"
    cd ..
    for name in "${namelist[@]}"; do
      mv "pinot/$name" commit_jars_new # move them into folder in the base repo
    done
  fi
  cd pinot || exit
  git checkout "${hashlist[$i]}"
  mvn clean install -DskipTests -q
  echo "mvn clean #""$i"" done"
  paths2="$(find . -type f -name "*${version}.jar" -print | tr "\n" " ")"
  IFS=' ' read -r -a namelist2 <<< "$paths2"
  cd ..
  for name in "${namelist2[@]}"; do
    mv "pinot/$name" commit_jars_old
  done

  # fail process if either temp directory doesn't have files, meaning something went wrong
  if [ -z "$( ls -A 'commit_jars_new' )" ]; then
      echo "The jars for the latest PR were not collected properly. Please investigate the cause of this."
      exit 1
  elif [ -z "$( ls -A 'commit_jars_old' )" ]; then
      echo "The jars for the second-latest PR were not collected properly. Please investigate the cause of this."
      exit 1
  fi

  # generate japicmp reports for each file
  touch pr-"$latest_pr".txt
  for filename in commit_jars_new/*; do
    name="$(basename "$filename")"
    if [ ! -f commit_jars_old/"$name" ]; then
      echo "It seems $name does not exist in the previous pull request. Please make sure this is intended." >> pr-"$latest_pr".txt
      echo "" >> pr-"$latest_pr".txt
      continue
    fi
    OLD=commit_jars_old/"$name"
    NEW=commit_jars_new/"$name"
    java -jar japicmp.jar \
      --old "$OLD" \
      --new "$NEW" \
      -a private \
      --no-annotations \
      --ignore-missing-classes \
      --only-modified >> pr-"$latest_pr".txt
  done

  # create json
  metadata=$(gh pr view "$latest_pr" -R apache/pinot --json title,number,mergedAt,files,url -q '.files |= [.[] | .path]')
  node scripts/parse_japicmp.js \
    --input pr-"$latest_pr".txt \
    --metadata "$metadata" \
    --output pr-"$latest_pr".json

  mv pr-"$latest_pr".txt data/japicmp
  mv pr-"$latest_pr".json data/output

  # move commit_jars_old to commit_jars_new
  # since the "old" PR is now being analyzed for changes
  rm -rf commit_jars_new/*
  mv commit_jars_old/* commit_jars_new
done

echo "done with file generation"
# "unclone" repos
rm -rf pinot

# remove temp directories
rm -rf commit_jars_old
rm -rf commit_jars_new
