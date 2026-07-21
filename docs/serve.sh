#!/bin/sh
# Local preview of the Reclaim marketing site.
cd "$(dirname "$0")"
echo "Reclaim site → http://localhost:8787"
exec python3 -m http.server 8787
