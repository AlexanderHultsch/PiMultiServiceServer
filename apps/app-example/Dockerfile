# Basis: Node.js LTS auf Alpine (klein, arm64-tauglich fuer den Pi).
FROM node:24-alpine

WORKDIR /app

# Erst nur package.json kopieren (Docker-Layer-Cache). Diese Beispiel-App hat
# keine Abhaengigkeiten; sobald du welche hinzufuegst, die naechste Zeile
# einkommentieren:
COPY package.json ./
# RUN npm install --omit=dev

COPY server.js ./

# Als unprivilegierter Nutzer laufen (Alpine-Node-Image bringt "node" mit).
USER node

EXPOSE 3000
CMD ["node", "server.js"]
