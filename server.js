const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

// Serve static files from "public" directory (like index.html)
app.use(express.static(path.join(__dirname, 'public')));

// Serve the JSON files statically from "data" folder
const dataDir = path.join(__dirname, 'data');
app.use('/data', express.static(dataDir));

// Endpoint to list JSON filenames in ./data
app.get('/list-files', (req, res) => {
  fs.readdir(dataDir, (err, files) => {
    if (err) {
      console.error('Error reading data directory:', err);
      return res.status(500).json({ error: 'Could not read directory' });
    }
    const jsonFiles = files.filter(file => file.endsWith('.json'));
    res.json(jsonFiles);
  });
});

app.listen(PORT, () => {
  console.log(`✅ Server is running at http://localhost:${PORT}`);
});
