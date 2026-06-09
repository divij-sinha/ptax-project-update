#!/bin/bash

cd /srv/shared/apps/ptax-project-update
git pull
uv sync
Rscript -e "renv::restore(prompt = FALSE)"

sudo systemctl restart ptax-rq.service
sudo systemctl restart ptaxproject.service
