// Local-only media origins for browser regressions. No external services.
import http from 'node:http';
import { readFileSync } from 'node:fs';
const files = new Map(['red_blue.webm', 'red_blue.mp4', 'red_blue_vp9.webm', 'red_blue_live.webm']
  .map(name => [name, readFileSync(new URL(`../test/fixtures/${name}`, import.meta.url))]));
for (const [port, cors] of [[18761, true], [18762, false]]) {
  http.createServer((req, res) => {
    if (cors) res.setHeader('Access-Control-Allow-Origin', '*');
    const name = new URL(req.url, 'http://localhost').pathname.slice(1);
    if (name === 'stall') { req.on('close', () => res.destroy()); return; }
    if (name === 'disconnect') { req.socket.destroy(); return; }
    const bytes = files.get(name);
    if (!bytes) { res.writeHead(404); res.end('Missing'); return; }
    res.setHeader('Content-Type', name.endsWith('.mp4') ? 'video/mp4' : 'video/webm');
    res.setHeader('Accept-Ranges', 'bytes');
    const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range ?? '');
    const start = range ? Number(range[1]) : 0;
    const end = range?.[2] ? Math.min(Number(range[2]), bytes.length - 1) : bytes.length - 1;
    if (start > end) { res.writeHead(416); res.end(); return; }
    if (range) res.setHeader('Content-Range', `bytes ${start}-${end}/${bytes.length}`);
    res.setHeader('Content-Length', end - start + 1);
    res.writeHead(range ? 206 : 200); res.end(bytes.subarray(start, end + 1));
  }).listen(port, '127.0.0.1', () => console.log(`Fixture origin http://127.0.0.1:${port}, CORS=${cors}`));
}
