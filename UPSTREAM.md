# Upstream

ChillZone is a fork of Olympus: https://github.com/dnl-gentile/olympus-addon (git remote `upstream`).

Base: `ed7a81e`, Olympus 1.5.1 (2026-11-05).

Commits are taken one by one with `bash scripts/port-upstream.sh <commit>|<from>..<to>`, which
rebrands each patch (`scripts/rebrand.py patch`) and applies it; it adds a row below for each.

| Upstream | ChillZone | Subject |
|---|---|---|
