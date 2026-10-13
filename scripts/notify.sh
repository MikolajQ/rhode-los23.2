#!/usr/bin/env bash
# Powiadomienie na telefon przez ntfy.sh: temat z argumentu ntfy_topic w ham.yml (HAM eksportuje go jako
# NTFY_TOPIC); w aplikacji ntfy subskrypcja tego tematu. Bez tematu nic nie robi. Temat jest jedynym
# zabezpieczeniem (kto go zna, czyta powiadomienia), więc losowy i nigdzie publicznie; treść bez sekretów.
# JSON zamiast nagłówków HTTP: nagłówki nie przeniosą polskich znaków.
# Użycie: notify.sh <tytuł> <treść> [default|high|urgent]. Nigdy nie kończy się błędem.
TITLE=${1:-build}; MSG=${2:-}; PRIO=${3:-default}
[ -n "${NTFY_TOPIC:-}" ] || exit 0
DEV=$(. "$(dirname "$0")/device.env" 2>/dev/null; echo "${DEVICE:-}")
python3 - "$NTFY_TOPIC" "${DEV:+[$DEV] }$TITLE" "$MSG" "$PRIO" <<'PY' | curl -fsS --max-time 20 --retry 3 --retry-all-errors \
    -H 'Content-Type: application/json' --data-binary @- https://ntfy.sh/ >/dev/null 2>&1 || echo "notify: ntfy niedostępny"
import json, sys
topic, title, msg, prio = sys.argv[1:5]
print(json.dumps({"topic": topic, "title": title, "message": msg or title,
                  "priority": {"default": 3, "high": 4, "urgent": 5}.get(prio, 3), "tags": ["robot"]}))
PY
exit 0
