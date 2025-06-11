const fs   = require('fs');
const path = require('path');

const dataDir = path.join(__dirname, '..', 'data');
const outFile = path.join(dataDir, 'manifest.json');

const files = fs
    .readdirSync(dataDir)
    .filter(f => f.endsWith('.json') && f !== 'manifest.json');

// If you want just names:
const manifest = files;

fs.writeFileSync(outFile, JSON.stringify(manifest, null, 2));
console.log(`Wrote ${files.length} entries to ${outFile}`);
