// Winzige dynamische Beispiel-App - nur Node-Standardbibliothek, keine Abhaengigkeiten.
// Zweck: zeigt, dass eine dynamische App (eigener Container, hinter Caddy) funktioniert.
// Ersetze den Inhalt durch deine echte App (Express, Fastify, o. ae.).
const http = require("http");

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(`<!doctype html>
<html lang="de">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dynamische Beispiel-App</title>
<style>
  :root { color-scheme: light dark; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         font-family:system-ui,-apple-system,"Segoe UI",sans-serif; background:#0b1020; color:#e8ecf7; text-align:center; }
  main { padding:2rem; max-width:40rem; }
  h1 { font-size:1.75rem; margin-bottom:0.5rem; }
  p { color:#9aa4c0; line-height:1.5; }
  code { background:#1a2138; padding:0.1rem 0.3rem; border-radius:4px; }
</style></head>
<body><main>
  <h1>Dynamische App läuft ✅</h1>
  <p>Serverzeit bei diesem Aufruf: <code>${new Date().toISOString()}</code></p>
  <p>Diese Seite wird bei <em>jedem</em> Aufruf neu erzeugt — im Gegensatz zu den
     statischen Seiten. Code liegt in <code>apps/app-example/</code>.</p>
</main></body></html>`);
});

server.listen(PORT, () => console.log(`app-example läuft auf Port ${PORT}`));
