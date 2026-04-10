#!/bin/bash
# Deploy backend and frontend App Services, plus Function App.
# Usage: ./scripts/deploy_apps.sh <backend-app-name> <frontend-app-name> <function-app-name>
#
# Requires: Azure CLI (az) logged in, and the infrastructure already provisioned.

set -euo pipefail

BACKEND_APP="${1:?Usage: deploy_apps.sh <backend-app-name> <frontend-app-name> <function-app-name>}"
FRONTEND_APP="${2:?}"
FUNCTION_APP="${3:?}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying backend to $BACKEND_APP ==="
cd "$ROOT_DIR/backend"
zip -r /tmp/backend.zip . -x '__pycache__/*' '*.pyc' '.env'
az webapp deployment source config-zip --name "$BACKEND_APP" --resource-group rg-indexer-demo --src /tmp/backend.zip
rm /tmp/backend.zip
echo "[OK] Backend deployed."

echo ""
echo "=== Deploying frontend to $FRONTEND_APP ==="
cd "$ROOT_DIR/frontend"
zip -r /tmp/frontend.zip . -x '__pycache__/*' '*.pyc'
az webapp deployment source config-zip --name "$FRONTEND_APP" --resource-group rg-indexer-demo --src /tmp/frontend.zip
rm /tmp/frontend.zip
echo "[OK] Frontend deployed."

echo ""
echo "=== Deploying Function App to $FUNCTION_APP ==="
cd "$ROOT_DIR/function-app"
func azure functionapp publish "$FUNCTION_APP"
echo "[OK] Function App deployed."

echo ""
echo "Done. Access the frontend at: https://$FRONTEND_APP.azurewebsites.net"
