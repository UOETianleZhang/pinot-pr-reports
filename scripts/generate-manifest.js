const fs   = require('fs');
const path = require('path');

const dataDir = path.join(__dirname, '..', 'data');
const outFile = path.join(dataDir, 'manifest.json');

if (!fs.existsSync(dataDir)) {
  console.log(`'data' folder not found at ${dataDir}, creating it.`);
  fs.mkdirSync(dataDir, { recursive: true });
}

const files = fs
    .readdirSync(dataDir)
    .filter(f => f.endsWith('.json') && f !== 'manifest.json');

if (files.length === 0) {
  console.warn("⚠️ No JSON files found in data folder to add to manifest.");
}

// If you want just names:
const manifest = files;

fs.writeFileSync(outFile, JSON.stringify(manifest, null, 2));
console.log(`Wrote ${files.length} entries to ${outFile}`);
