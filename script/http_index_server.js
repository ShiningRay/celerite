// Minimal static file server for the compact-index differential fixture.
// Serves a directory (fixtures/gem-index) over HTTP so both engines exercise
// the v2 compact-index protocol (created_at metadata for cooldown) against a
// real HTTP remote instead of the file:// v1 marshal index.
const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[2]);
const port = parseInt(process.argv[3] || "8765", 10);

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, "http://x").pathname);
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
