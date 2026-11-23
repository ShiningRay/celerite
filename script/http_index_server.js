// Minimal static file server for the compact-index differential fixture.
// Serves a directory (fixtures/gem-index) over HTTP so both engines exercise
// the v2 compact-index protocol (created_at metadata for cooldown) against a
// real HTTP remote instead of the file:// v1 marshal index.
//
// Optional third argument: a status-map file. Each non-blank, non-`#` line is
// `<path-prefix><TAB><code>`; a request whose URL path starts with the prefix
// gets that status instead of the file, and the longest matching prefix wins.
// This lets private-source fixtures pin 401/403 behaviour that a plain static
// root cannot express. A missing or malformed map degrades to the original
// 200/404 server and prints one stderr warning; it never crashes, so every
// fixture without a map keeps its previous behaviour.
const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[2]);
const port = parseInt(process.argv[3] || "8765", 10);

function load_status_map(file) {
  if (!file) return [];
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (err) {
    console.error(`http_index_server: cannot read status map ${file}: ${err.message}`);
    return [];
  }
  const entries = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) continue;
    const tab = line.indexOf("\t");
    const prefix = tab < 0 ? "" : line.slice(0, tab).trim();
    const code_text = tab < 0 ? "" : line.slice(tab + 1).trim();
    const code = Number(code_text);
    if (prefix === "" || !/^\d{3}$/.test(code_text) || code < 100 || code > 599) {
      console.error(`http_index_server: malformed status map line ${JSON.stringify(raw)}; serving without status overrides`);
      return [];
    }
    entries.push({ prefix, code });
  }
  return entries;
}

const statuses = load_status_map(process.argv[4]);

function status_for(url_path) {
  let best = null;
  for (const entry of statuses) {
    if (url_path.startsWith(entry.prefix) && (best === null || entry.prefix.length > best.prefix.length)) {
      best = entry;
    }
  }
  return best;
}

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const override = status_for(urlPath);
  if (override) {
    const body = "denied\n";
    const headers = {
      "Content-Type": "text/plain",
      "Content-Length": String(Buffer.byteLength(body)),
      Connection: "close",
    };
    if (override.code === 401) {
      headers["WWW-Authenticate"] = 'Basic realm="private"';
    }
    res.writeHead(override.code, headers);
    res.end(body);
    return;
  }
  const file = path.join(root, urlPath);
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { "Content-Length": "9", Connection: "close" });
      res.end("Not Found");
      return;
    }
    res.writeHead(200, { "Content-Length": data.length, Connection: "close" });
    res.end(data);
  });
});
server.listen(port, "127.0.0.1");
