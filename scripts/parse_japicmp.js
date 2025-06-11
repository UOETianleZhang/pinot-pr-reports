#!/usr/bin/env node

/**
 * parse_japicmp.js
 *
 * Reads a plain-text japicmp diff and outputs
 * a JSON report listing each modified class/interface,
 * whether it's compatible, and its added/removed methods and fields.
 *
 * Usage:
 *   node ./parse_japicmp.js \
 *   --input data/japicmp/pr-{pr_number}.txt \
 *   --metadata [variable representing line of gh cli code]
 *   --output data/output/pr-{pr_number}.json \
 */

const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);
let inputPath;
let outputPath;
let metadata;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--input' || args[i] === '-i') {
    inputPath = args[++i];
  } else if (args[i] === '--metadata' || args[i] === '-m') {
    metadata = args[++i];
  } else if (args[i] === '--output' || args[i] === '-o') {
    outputPath = args[++i];
  }
}

if (!inputPath || !metadata) {
  console.error('Usage: parse_japicmp.js --input <INPUT_PATH> --metadata <METADATA> [--output <OUTPUT_PATH>]');
  process.exit(1);
}

if (!fs.existsSync(inputPath)) {
  console.error(`Error: Input file not found: ${inputPath}`);
  process.exit(1);
}

const content = fs.readFileSync(inputPath, 'utf8');
const lines = content.split(/\r?\n/);

const classes = [];
let current = null;
let names = [];

for (const line of lines) {
  // Example header: ***! MODIFIED CLASS/INTERFACE: ... (not serializable)
  const modifMatch = line.match(/^\*+!?\s+MODIFIED (?:CLASS|INTERFACE):\s+(.+?)\s+\(/);
  const newMatch = line.match(/^\++!?\s+NEW (?:CLASS|INTERFACE):\s+(.+?)\s+\(/);
  const removeMatch = line.match(/^-+!?\s+REMOVED (?:CLASS|INTERFACE):\s+(.+?)\s+\(/);

  if (modifMatch) {
    const fullNamePart = modifMatch[1].trim();
    const parts = fullNamePart.split(/\s+/);
    const className = parts[parts.length - 1];
    current = {
      className,
      type: "modification",
      compatible: true,
      removedMethods: [],
      addedMethods: [],
      removedFields: [],
      addedFields: [],
      removedConstructors: [],
      addedConstructors: []
    };
    classes.push(current);
    continue;
  } else if (newMatch) {
    const fullNamePart = newMatch[1].trim();
    const parts = fullNamePart.split(/\s+/);
    const className = parts[parts.length - 1];
    current = {
      className,
      type: "addition",
      compatible: true,
      removedMethods: [],
      addedMethods: [],
      removedFields: [],
      addedFields: [],
      removedConstructors: [],
      addedConstructors: []
    };
    classes.push(current);
    continue;
  } else if (removeMatch) {
    const fullNamePart = removeMatch[1].trim();
    const parts = fullNamePart.split(/\s+/);
    const className = parts[parts.length - 1];
    current = {
      className,
      type: "deletion",
      compatible: false,
      removedMethods: [],
      addedMethods: [],
      removedFields: [],
      addedFields: [],
      removedConstructors: [],
      addedConstructors: []
    };
    classes.push(current);
    continue;
  }
  if (!current) continue;

  let match;
  if (match = line.match(/REMOVED METHOD:\s*(.*)/)) {
    current.removedMethods.push(match[1].trim());
    current.compatible = false;
    continue;
  }
  if (match = line.match(/NEW METHOD:\s*(.*)/)) {
    current.addedMethods.push(match[1].trim());
    continue;
  }
  if (match = line.match(/REMOVED FIELD:\s*(.*)/)) {
    current.removedFields.push(match[1].trim());
    current.compatible = false;
    continue;
  }
  if (match = line.match(/NEW FIELD:\s*(.*)/)) {
    current.addedFields.push(match[1].trim());
    continue;
  }
  if (match = line.match(/REMOVED CONSTRUCTOR:\s*(.*)/)) {
    current.removedConstructors.push(match[1].trim());
    current.compatible = false;
    continue;
  }
  if (match = line.match(/NEW CONSTRUCTOR:\s*(.*)/)) {
    current.addedConstructors.push(match[1].trim());
    continue;
  }
}

const report = { ...JSON.parse(metadata), jcmpClasses: classes };
const outJson = JSON.stringify(report, null, 2);

if (outputPath) {
  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(outputPath, outJson, 'utf8');
  console.log(`Wrote JSON report to ${outputPath}`);
} else {
  console.log(outJson);
}