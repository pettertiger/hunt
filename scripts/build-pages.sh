#!/bin/sh
set -eu

: "${SUPABASE_URL:?Set the Supabase production URL in Cloudflare Pages build variables}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set a Supabase publishable key in Cloudflare Pages build variables}"

python3 <<'PYTHON'
import base64
import json
import os
from pathlib import Path
from urllib.parse import urlparse

url = urlparse(os.environ["SUPABASE_URL"])
key = os.environ["SUPABASE_PUBLISHABLE_KEY"]

if url.scheme != "https" or not url.netloc or url.username or url.password:
    raise SystemExit("SUPABASE_URL must be an HTTPS URL without credentials")

is_publishable = key.startswith("sb_publishable_")
if not is_publishable and not key.startswith("sb_secret_"):
    parts = key.split(".")
    if len(parts) == 3:
        try:
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + "==="))
            is_publishable = payload.get("role") == "anon"
        except (ValueError, json.JSONDecodeError):
            pass
if not is_publishable:
    raise SystemExit("Use a publishable key or legacy anon key; secret/service-role keys are forbidden")

Path("dist").mkdir(exist_ok=True)
for filename in ("index.html", "map-editor.html", "_headers"):
    Path("dist", filename).write_bytes(Path(filename).read_bytes())

config = {"supabaseUrl": url.geturl().rstrip("/"), "publishableKey": key}
Path("dist/config.js").write_text(
    "window.HUNT_CONFIG = Object.freeze(" + json.dumps(config, ensure_ascii=True) + ");\n",
    encoding="utf-8",
)
PYTHON
