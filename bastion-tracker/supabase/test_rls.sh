#!/usr/bin/env bash
# Proves row security, roles, revision conflicts, and one-time sale settlement.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d /usr/lib/postgresql ]]; then
  PGVER="$(ls /usr/lib/postgresql | head -n 1)"
  export PATH="/usr/lib/postgresql/${PGVER}/bin:${PATH}"
fi
PORT="${PGPORT:-55432}"
DATA="${PGDATA:-/tmp/bastion-pg}"
LOG="${PGLOG:-/tmp/bastion-pg.log}"

if ! command -v initdb >/dev/null 2>&1; then
  echo "PostgreSQL client tools are required." >&2
  exit 1
fi

if [[ ! -d "$DATA" ]]; then
  initdb -D "$DATA" --auth=trust --username="$(whoami)" >/dev/null
fi
if ! pg_isready -h 127.0.0.1 -p "$PORT" >/dev/null 2>&1; then
  pg_ctl -D "$DATA" -l "$LOG" -o "-p $PORT -k /tmp" start >/dev/null
fi

dropdb -h 127.0.0.1 -p "$PORT" --if-exists bastion_rls_test
createdb -h 127.0.0.1 -p "$PORT" bastion_rls_test
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f harness.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/001_bastion.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/002_pin_empty_document_search_path.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/003_command_parity.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/004_remove_blank_goods.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/005_remove_person.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/006_manage_rooms_people.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f migrations/007_bastion_turns.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f rls_test.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f command_test.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f goods_test.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f person_test.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f manage_test.sql
psql -h 127.0.0.1 -p "$PORT" -d bastion_rls_test -v ON_ERROR_STOP=1 -f turn_test.sql
echo "database isolation tests passed"
