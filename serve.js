#!/usr/bin/env node
// Dev server: compiles Elm in debug mode, watches src/ for changes, serves with SPA fallback.
const http  = require('http');
const fs    = require('fs');
const path  = require('path');
const { execFile, spawn } = require('child_process');

const PORT   = 3000;
const ROOT   = __dirname;
const SRC    = path.join(ROOT, 'src');
const OUTPUT = path.join(ROOT, 'main.js');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript',
  '.css':  'text/css',
  '.json': 'application/json',
  '.png':  'image/png',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.woff2':'font/woff2',
  '.woff': 'font/woff',
};

// ── Elm compiler ──────────────────────────────────────────────────────────────

let compiling = false;

function compile(label) {
  if (compiling) return;
  compiling = true;
  process.stdout.write(`elm ${label}... `);
  execFile('elm', ['make', 'src/Main.elm', '--output=main.js', '--debug'], { cwd: ROOT }, (err, _stdout, stderr) => {
    compiling = false;
    if (err) {
      console.error('\n' + stderr);
    } else {
      console.log('ok');
    }
  });
}

// Initial compile
compile('compiling');

// Watch src/ for changes
fs.watch(SRC, { recursive: true }, (event, filename) => {
  if (filename && filename.endsWith('.elm')) {
    compile(`recompiling (${filename})`);
  }
});

// ── HTTP server ───────────────────────────────────────────────────────────────

http.createServer((req, res) => {
  const urlPath = req.url.split('?')[0];
  let filePath  = path.join(ROOT, urlPath === '/' ? 'index.html' : urlPath);

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) filePath = path.join(ROOT, 'index.html');

    fs.readFile(filePath, (err2, data) => {
      if (err2) { res.writeHead(500); res.end('Server error'); return; }
      const ext  = path.extname(filePath);
      const type = MIME[ext] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' });
      res.end(data);
    });
  });
}).listen(PORT, () => {
  console.log(`http://localhost:${PORT}`);
});
