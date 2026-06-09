#!/bin/bash

PATH="/opt/quarto/1.10.9/bin:$PATH"  exec /srv/shared/apps/ptax-project-update/.venv/bin/rq worker-pool -n 8
