#!/bin/bash

# Usage: source ./prepare-testing.sh [SERVER_URL] [CONSOLE_PASSWORD] [-o]

# Get some of the variables from parameters
if [[ $# -lt 1 ]]; then
    echo "Info: SERVER_URL not set. Assuming local testing."
    SERVER_URL="http://localhost:8080"
    AUTH_REQUIRED="false"
else
    SERVER_URL="$1"
    AUTH_REQUIRED="true"
fi

if [[ $# -lt 2 ]]; then
    echo "Info: CONSOLE_PASSWORD not set."
else
    CONSOLE_PASSWORD="$2"
fi

# Check for optional -o flag
if [[ "$*" == *"-o"* ]]; then
    PLAYWRIGHT_PASSWORD="admin123456"
else
    PLAYWRIGHT_PASSWORD="Admin@123"
fi

# Get API URL from SERVER_URL
SERVER_URL="${SERVER_URL#https://}"
API_URL="${SERVER_URL%/*}" # Remove everything after last slash
API_URL="${API_URL/*apps/api}" # Replace 'apps' and everything left of it with 'api'
API_URL="${API_URL}:6443" # Add port 6443
# echo "API_URL: $API_URL"

# Get project from SERVER_URL
# Extract the part after 'server-' and remove everything after the next dot
PROJECT="${SERVER_URL#*server-}" # Remove everything up to and including 'server-'
PROJECT="${PROJECT%%.*}" # Remove everything from the next dot onward
# echo "PROJECT: $PROJECT"

oc login "$SERVER_URL" -u kubeadmin -p "$CONSOLE_PASSWORD" --insecure-skip-tls-verify=true 2>/dev/null
# oc login "$API_URL" -u kubeadmin -p "$CONSOLE_PASSWORD" --insecure-skip-tls-verify=true
oc project "$PROJECT" 2>/dev/null
# oc project "$PROJECT"
OIDC_OUTPUT=$(oc get secret oidc-cli -o json | jq -r '.data | to_entries | map( (.key|sub("[.-]"; "_")) + "=" + (.value | @base64d) )[]')

# Set the variables
TRUSTIFY_UI_URL=$SERVER_URL
export TRUSTIFY_UI_URL
TRUSTIFY_API_URL=$SERVER_URL
export TRUSTIFY_API_URL
export AUTH_REQUIRED
PLAYWRIGHT_AUTH_USER="admin"
export PLAYWRIGHT_AUTH_USER
PLAYWRIGHT_AUTH_PASSWORD="$PLAYWRIGHT_PASSWORD"
export PLAYWRIGHT_AUTH_PASSWORD
PLAYWRIGHT_AUTH_CLIENT_ID=$(echo "$OIDC_OUTPUT" | sed -n '1p' | sed 's/^[^=]*=//')
SECOND_LINE=$(echo "$OIDC_OUTPUT" | sed -n '2p' | sed 's/^[^=]*=//')
if [[ -z "$SECOND_LINE" ]]; then
    PLAYWRIGHT_AUTH_CLIENT_SECRET=$(echo "$OIDC_OUTPUT" | sed -n '3p' | sed 's/^[^=]*=//')
else
    PLAYWRIGHT_AUTH_CLIENT_SECRET="$SECOND_LINE"
fi
export PLAYWRIGHT_AUTH_CLIENT_ID
export PLAYWRIGHT_AUTH_CLIENT_SECRET

# Display exported variables
echo " "
echo "Test environment configuration:"
echo "================================"
echo "TRUSTIFY_UI_URL=$TRUSTIFY_UI_URL"
echo "TRUSTIFY_API_URL=$TRUSTIFY_API_URL"
echo "AUTH_REQUIRED=$AUTH_REQUIRED"
echo "PLAYWRIGHT_AUTH_USER=$PLAYWRIGHT_AUTH_USER"
echo "PLAYWRIGHT_AUTH_PASSWORD=$PLAYWRIGHT_AUTH_PASSWORD"
echo "PLAYWRIGHT_AUTH_CLIENT_ID=$PLAYWRIGHT_AUTH_CLIENT_ID"
echo "PLAYWRIGHT_AUTH_CLIENT_SECRET=$PLAYWRIGHT_AUTH_CLIENT_SECRET"
