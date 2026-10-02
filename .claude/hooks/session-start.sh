#!/bin/bash
# SessionStart hook for Claude Code cloud sessions.
# Installs project dependencies from whichever manifests are present, so that
# tests and linters work. Idempotent and non-interactive; no-ops when the
# repository has no manifests yet.
set -euo pipefail

# Only run in Claude Code cloud (remote) sessions.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

log() { echo "[session-start] $*" >&2; }

# --- Python ----------------------------------------------------------------
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f requirements-dev.txt ] \
   || [ -f environment.yml ] || [ -f environment.yaml ]; then
  PIP="python3 -m pip"
  PIP_OPTS="--disable-pip-version-check --quiet"

  if [ -f environment.yml ] || [ -f environment.yaml ]; then
    ENV_FILE=$(ls environment.y*ml | head -n1)
    if command -v mamba >/dev/null 2>&1; then
      log "Updating conda environment from $ENV_FILE (mamba)"
      mamba env update --file "$ENV_FILE" --prune --quiet
    elif command -v conda >/dev/null 2>&1; then
      log "Updating conda environment from $ENV_FILE (conda)"
      conda env update --file "$ENV_FILE" --prune --quiet
    else
      log "$ENV_FILE found but conda/mamba not available; falling back to pip manifests"
    fi
  fi

  if [ -f requirements.txt ]; then
    log "Installing requirements.txt"
    $PIP install $PIP_OPTS -r requirements.txt
  fi
  if [ -f requirements-dev.txt ]; then
    log "Installing requirements-dev.txt"
    $PIP install $PIP_OPTS -r requirements-dev.txt
  fi
  if [ -f pyproject.toml ]; then
    log "Installing project from pyproject.toml (editable, with dev extras if defined)"
    $PIP install $PIP_OPTS -e ".[dev]" 2>/dev/null || $PIP install $PIP_OPTS -e .
  fi

  # Make the repository importable for tests run from the root.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo 'export PYTHONPATH="${CLAUDE_PROJECT_DIR:-.}${PYTHONPATH:+:$PYTHONPATH}"' >> "$CLAUDE_ENV_FILE"
  fi
fi

# --- Node.js ---------------------------------------------------------------
if [ -f package.json ]; then
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    log "Installing Node dependencies (pnpm)"
    pnpm install
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    log "Installing Node dependencies (yarn)"
    yarn install
  else
    log "Installing Node dependencies (npm)"
    npm install --no-audit --no-fund
  fi
fi

# --- R ---------------------------------------------------------------------
if [ -f renv.lock ] && command -v Rscript >/dev/null 2>&1; then
  log "Restoring R packages from renv.lock"
  Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos = "https://cloud.r-project.org"); renv::restore(prompt = FALSE)'
fi

log "Done."
