#!/bin/sh
set -e

UUID="${UUID:-d342d11e-d424-4583-b36e-524ab1f0afa4}"
PORT="${PORT:-8080}"
GRPC_SERVICE="${GRPC_SERVICE:-api}"

echo "[ewp] PORT=${PORT} SERVICENAME=${GRPC_SERVICE}"

cat > /tmp/config.json << CFEOF
{
  "log": { "level": "info", "timestamp": true },
  "listener": {
    "port": ${PORT},
    "address": "0.0.0.0",
    "modes": ["grpc"],
    "grpc_service": "${GRPC_SERVICE}"
  },
  "protocol": {
    "type": "ewp",
    "uuid": "${UUID}",
    "enable_flow": true
  }
}
CFEOF

echo "[ewp] config.json generated"
exec /app/ewp-server -c /tmp/config.json
