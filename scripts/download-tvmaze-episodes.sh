#!/usr/bin/env bash

ROOT="${TVMAZE_ROOT:?TVMAZE_ROOT is required}"
IDS="${TVMAZE_IDS:?TVMAZE_IDS is required}"

DEST_DIR="$ROOT/episodes"
LOG="$ROOT/episodes-download.log"
FAILED="$ROOT/episodes-failed.log"
NOT_FOUND="$ROOT/episodes-not-found.log"
ERRORS="$ROOT/logs/episodes-errors.txt"

mkdir -p "$DEST_DIR" "$ROOT/logs"

touch "$LOG" "$FAILED" "$NOT_FOUND" "$ERRORS"

PROXY_ARGS=()

if [ -n "${TVMAZE_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$TVMAZE_PROXY")
fi

curl_api() {
    curl \
      "${PROXY_ARGS[@]}" \
      --http1.1 \
      --connect-timeout 15 \
      --max-time 60 \
      -sS \
      "$@"
}

if [ ! -f "$IDS" ]; then
    echo "$(date -Is) ids file not found: $IDS" >> "$ERRORS"
    exit 1
fi

PROBE_HTTP="$(
    curl_api \
      -o /dev/null \
      -w '%{http_code}' \
      'https://api.tvmaze.com/shows/1/episodes?specials=1' \
      2>>"$ERRORS"
)"

if [ "$PROBE_HTTP" != "200" ]; then
    echo "$(date -Is) API probe failed http=$PROBE_HTTP" >> "$ERRORS"
    exit 1
fi

TOTAL="$(grep -Ec '^[0-9]+$' "$IDS" 2>/dev/null)"

DONE=0
DOWNLOADED=0
SKIPPED=0
FAILED_COUNT=0
NOT_FOUND_COUNT=0

echo "$(date -Is) start total=$TOTAL" >> "$LOG"

while IFS= read -r SHOW_ID; do
    case "$SHOW_ID" in
        ''|*[!0-9]*)
            continue
            ;;
    esac

    DONE=$((DONE + 1))

    DEST="$DEST_DIR/$SHOW_ID.json"
    TMP="$DEST_DIR/.$SHOW_ID.part"

    if [ -s "$DEST" ]; then
        if python3 - "$DEST" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

if not isinstance(data, list):
    raise SystemExit(1)
PY
        then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    ATTEMPT=1
    SUCCESS=0

    while [ "$ATTEMPT" -le 6 ]; do
        rm -f "$TMP"

        HTTP="$(
            curl_api \
              -o "$TMP" \
              -w '%{http_code}' \
              "https://api.tvmaze.com/shows/${SHOW_ID}/episodes?specials=1" \
              2>>"$ERRORS"
        )"

        if [ "$HTTP" = "200" ]; then
            if python3 - "$TMP" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

if not isinstance(data, list):
    raise SystemExit(1)
PY
            then
                mv "$TMP" "$DEST"
                DOWNLOADED=$((DOWNLOADED + 1))
                SUCCESS=1
                break
            else
                echo "$(date -Is) show=$SHOW_ID invalid_json attempt=$ATTEMPT" >> "$ERRORS"
            fi

        elif [ "$HTTP" = "404" ]; then
            echo "$SHOW_ID" >> "$NOT_FOUND"
            NOT_FOUND_COUNT=$((NOT_FOUND_COUNT + 1))
            rm -f "$TMP"
            SUCCESS=1
            break

        elif [ "$HTTP" = "429" ]; then
            echo "$(date -Is) show=$SHOW_ID http=429 attempt=$ATTEMPT" >> "$LOG"
            rm -f "$TMP"
            sleep 10

        elif [ "$HTTP" = "000" ]; then
            echo "$(date -Is) show=$SHOW_ID http=000 attempt=$ATTEMPT" >> "$ERRORS"
            rm -f "$TMP"
            sleep 5

        elif [ "$HTTP" -ge 500 ] 2>/dev/null; then
            echo "$(date -Is) show=$SHOW_ID http=$HTTP attempt=$ATTEMPT" >> "$ERRORS"
            rm -f "$TMP"
            sleep 5

        else
            echo "$(date -Is) show=$SHOW_ID http=$HTTP attempt=$ATTEMPT" >> "$ERRORS"
            rm -f "$TMP"
            break
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    if [ "$SUCCESS" -ne 1 ]; then
        echo "show id=$SHOW_ID" >> "$FAILED"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    if [ $((DONE % 250)) -eq 0 ]; then
        echo "$(date -Is) progress=$DONE/$TOTAL downloaded=$DOWNLOADED skipped=$SKIPPED failed=$FAILED_COUNT not_found=$NOT_FOUND_COUNT" >> "$LOG"
    fi

    sleep 0.65

done < "$IDS"

echo "$(date -Is) finished total=$TOTAL downloaded=$DOWNLOADED skipped=$SKIPPED failed=$FAILED_COUNT not_found=$NOT_FOUND_COUNT" >> "$LOG"

exit 0
