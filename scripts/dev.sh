#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PennyWise – start everything for local development with ONE command.
#
#   ./scripts/dev.sh                 # pick a device interactively (flutter's prompt)
#   ./scripts/dev.sh -d macos        # any `flutter run` arguments are passed through
#   ./scripts/dev.sh -d <iphone-id>  # real phone: API_URL is set to your Mac's Wi-Fi IP
#   API_URL=https://api.example.com ./scripts/dev.sh   # use a deployed API instead
#
# What it does:
#   1. installs backend packages and creates backend/.env if missing
#   2. starts the Node API (npm run dev) unless it is already running
#   3. waits until http://localhost:3000/api/health answers
#   4. runs `flutter run` with the right API_URL for the chosen device
#   5. stops the API again when you quit Flutter (only if this script started it)
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
PORT="${PORT:-3000}"
HEALTH="http://localhost:$PORT/api/health"
LOG="$BACKEND/.dev-server.log"

blue() { printf '\033[34m▶ %s\033[0m\n' "$*"; }
red()  { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; }

command -v node >/dev/null || { red "Node.js is not installed (need >= 20.6)."; exit 1; }
command -v flutter >/dev/null || { red "Flutter is not installed or not on PATH."; exit 1; }

# 1. backend setup -----------------------------------------------------------
if [[ ! -d "$BACKEND/node_modules" ]]; then
  blue "Installing backend packages…"
  (cd "$BACKEND" && npm install --no-audit --no-fund)
fi
if [[ ! -f "$BACKEND/.env" ]]; then
  blue "Creating backend/.env from .env.example"
  cp "$BACKEND/.env.example" "$BACKEND/.env"
fi

# 2. start the API if it is not already up -----------------------------------
API_PID=""
cleanup() {
  if [[ -n "$API_PID" ]]; then
    blue "Stopping the API (pid $API_PID)…"
    kill "$API_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if curl -fsS -m 2 "$HEALTH" >/dev/null 2>&1; then
  blue "API already running on port $PORT – reusing it."
else
  blue "Starting the API on port $PORT (log: backend/.dev-server.log)…"
  (cd "$BACKEND" && exec npm run dev) >"$LOG" 2>&1 &
  API_PID=$!
  # 3. wait for /api/health (max ~20 s)
  for _ in $(seq 1 40); do
    if curl -fsS -m 1 "$HEALTH" >/dev/null 2>&1; then break; fi
    if ! kill -0 "$API_PID" 2>/dev/null; then
      red "The API crashed while starting. Last lines of the log:"
      tail -n 20 "$LOG" >&2
      API_PID=""
      exit 1
    fi
    sleep 0.5
  done
  curl -fsS -m 2 "$HEALTH" >/dev/null || { red "API did not start in time. See $LOG"; exit 1; }
  blue "API is up: $HEALTH"
fi

# 4. choose API_URL for the target device ------------------------------------
DEVICE=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -d | --device-id) DEVICE="${args[$((i + 1))]:-}" ;;
    -d=* | --device-id=*) DEVICE="${args[$i]#*=}" ;;
  esac
done

lan_ip() {
  ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null ||
    hostname -I 2>/dev/null | awk '{print $1}' || true
}

# Is the chosen device a REAL phone (not simulator/emulator/desktop/web)?
is_physical_phone() {
  [[ -z "$DEVICE" ]] && return 1
  flutter devices --machine 2>/dev/null | DEVICE="$DEVICE" node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      const want = process.env.DEVICE.toLowerCase();
      const list = JSON.parse(s.slice(s.indexOf("[")) || "[]");
      const d = list.find(x => x.id.toLowerCase() === want || x.name.toLowerCase().startsWith(want));
      const phone = d && !d.emulator && /^(ios|android)/.test(d.targetPlatform);
      process.exit(phone ? 0 : 1);
    });'
}

DEFINES=()
if [[ -n "${API_URL:-}" ]]; then
  DEFINES=(--dart-define="API_URL=$API_URL")
elif is_physical_phone; then
  IP="$(lan_ip)"
  if [[ -z "$IP" ]]; then
    red "Could not find this Mac's Wi-Fi IP. Pass API_URL=http://<ip>:$PORT yourself."
    exit 1
  fi
  DEFINES=(--dart-define="API_URL=http://$IP:$PORT")
  blue "Real phone detected – the app will call http://$IP:$PORT (phone and Mac must share the Wi-Fi)."
fi

# Web: use a FIXED port. Social login (Google/Facebook/Apple) sends the
# browser back to this exact address, and Supabase only allows addresses on
# its Redirect URLs list. Flutter would otherwise pick a random port each run.
WEB_PORT="${WEB_PORT:-5000}"
if [[ "$DEVICE" == chrome || "$DEVICE" == web-server || "$DEVICE" == edge ]] && [[ " $* " != *" --web-port"* ]]; then
  DEFINES+=(--web-port "$WEB_PORT")
  blue "Web app on http://localhost:$WEB_PORT (add http://localhost:$WEB_PORT/** to Supabase Redirect URLs for social login)."
fi

# 5. run the app --------------------------------------------------------------
cd "$ROOT"
blue "flutter run ${DEFINES[*]:-} $*"
flutter run ${DEFINES[@]+"${DEFINES[@]}"} "$@"
