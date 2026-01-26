#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_PATH="${ROOT_DIR}/supabase/schema.sql"
SEED_PATH="${ROOT_DIR}/supabase/seed.sql"
CONFIG_PATH="${ROOT_DIR}/supabase/config.toml"
PROJECT_REF_PATH="${ROOT_DIR}/supabase/.temp/project-ref"
MIGRATIONS_PATH="${ROOT_DIR}/supabase/migrations"
DB_URL="${SUPABASE_DB_URL:-}"

if [[ ! -f "${SCHEMA_PATH}" ]]; then
  echo "Schema file not found: ${SCHEMA_PATH}"
  exit 1
fi

if [[ ! -f "${SEED_PATH}" ]]; then
  echo "Seed file not found: ${SEED_PATH}"
  exit 1
fi

if command -v supabase >/dev/null 2>&1; then
  SUPPORTS_EXECUTE="false"
  SUPPORTS_DB_URL="false"
  SUPPORTS_PUSH="false"
  DB_HELP=""
  if DB_HELP=$(supabase db --help 2>/dev/null); then
    if echo "${DB_HELP}" | grep -q -E "^[[:space:]]*execute\b"; then
      SUPPORTS_EXECUTE="true"
    fi
    if echo "${DB_HELP}" | grep -q -E "^[[:space:]]*push\b"; then
      SUPPORTS_PUSH="true"
    fi
  fi

  if [[ "${SUPPORTS_EXECUTE}" == "true" ]]; then
    EXEC_HELP=""
    if EXEC_HELP=$(supabase db execute --help 2>/dev/null); then
      if echo "${EXEC_HELP}" | grep -q -- "--db-url"; then
        SUPPORTS_DB_URL="true"
      fi
    fi
  fi

  if [[ "${SUPPORTS_EXECUTE}" == "true" ]]; then
    if [[ "${SUPPORTS_DB_URL}" == "true" && -n "${DB_URL}" ]]; then
      supabase db execute --db-url "${DB_URL}" --file "${SCHEMA_PATH}"
      supabase db execute --db-url "${DB_URL}" --file "${SEED_PATH}"
      exit 0
    fi

    if [[ -f "${CONFIG_PATH}" || -f "${PROJECT_REF_PATH}" ]]; then
      supabase db execute --file "${SCHEMA_PATH}"
      supabase db execute --file "${SEED_PATH}"
      exit 0
    fi
  fi

  if [[ "${SUPPORTS_PUSH}" == "true" ]]; then
    if [[ -d "${MIGRATIONS_PATH}" && ( -f "${CONFIG_PATH}" || -f "${PROJECT_REF_PATH}" ) ]]; then
      supabase db push
      exit 0
    fi
  fi

  if [[ -z "${DB_URL}" ]]; then
    echo "SUPABASE_DB_URL is required unless the project is linked. Run: supabase link --project-ref YOUR_REF"
    exit 1
  fi
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql not found. Install PostgreSQL client tools or Supabase CLI."
  exit 1
fi

psql "${DB_URL}" -v ON_ERROR_STOP=1 -f "${SCHEMA_PATH}" -f "${SEED_PATH}"
