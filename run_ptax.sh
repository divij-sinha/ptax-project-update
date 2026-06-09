#!/bin/bash

export PATH="/opt/quarto/1.10.9/bin:$PATH"

export NO_PROXY="metadata.google.internal,169.254.169.254,localhost,127.0.0.1"
export no_proxy="$NO_PROXY"   # some libs read only the lowercase form

exec /srv/shared/apps/ptax-project-update/.venv/bin/uvicorn main:app --port 8080 --app-dir app --workers 4
