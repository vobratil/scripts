#!/bin/bash

# Script to send an API request with Authorization header
# Usage: ./send-api-request.sh <SERVER_URL> <ENDPOINT> <QUERY> [ADDITIONAL_PARAMETERS]

if [[ $# -lt 3 ]]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 <SERVER_URL> <ENDPOINT> <QUERY> [ADDITIONAL_PARAMETERS]"
    exit 1
fi

SERVER_URL="$1"
ENDPOINT="$2"
QUERY="$3"
ADDITIONAL_PARAMETERS="$4"

# Check if required environment variables are defined
if [[ -z "$PLAYWRIGHT_AUTH_CLIENT_ID" ]] || [[ -z "$PLAYWRIGHT_AUTH_CLIENT_SECRET" ]]; then
    echo "Error: PLAYWRIGHT_AUTH_CLIENT_ID and/or PLAYWRIGHT_AUTH_CLIENT_SECRET environment variables are not defined."
    exit 1
fi

# Determine auth URL: use PLAYWRIGHT_AUTH_URL if set, otherwise discover from the server's index.html
if [[ -n "$PLAYWRIGHT_AUTH_URL" ]]; then
    AUTH_URL="$PLAYWRIGHT_AUTH_URL"
else
    echo "PLAYWRIGHT_AUTH_URL not set. Discovering OIDC server URL from $SERVER_URL..."
    INDEX_HTML=$(curl -sk "$SERVER_URL")
    SERVER_CONFIG=$(echo "$INDEX_HTML" | grep -oP 'window\._env\s*=\s*"\K[^"]+')
    if [[ -z "$SERVER_CONFIG" ]]; then
        echo "Error: Could not extract window._env from $SERVER_URL"
        exit 1
    fi
    AUTH_URL=$(echo "$SERVER_CONFIG" | base64 -d | jq -r '.OIDC_SERVER_URL')
    if [[ -z "$AUTH_URL" ]] || [[ "$AUTH_URL" == "null" ]]; then
        echo "Error: Could not discover OIDC_SERVER_URL from server config"
        exit 1
    fi
fi

echo "Auth URL: $AUTH_URL"

# Discover the token endpoint via OIDC well-known configuration
TOKEN_ENDPOINT=$(curl -sk "${AUTH_URL}/.well-known/openid-configuration" | jq -r '.token_endpoint')
if [[ -z "$TOKEN_ENDPOINT" ]] || [[ "$TOKEN_ENDPOINT" == "null" ]]; then
    echo "Error: Could not discover token endpoint from ${AUTH_URL}/.well-known/openid-configuration"
    exit 1
fi

echo "Token endpoint: $TOKEN_ENDPOINT"

# Request token using client credentials grant
TOKEN_RESPONSE=$(curl -sk -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${PLAYWRIGHT_AUTH_CLIENT_ID}&client_secret=${PLAYWRIGHT_AUTH_CLIENT_SECRET}")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [[ -z "$TOKEN" ]] || [[ "$TOKEN" == "null" ]]; then
    echo "Error: Failed to retrieve access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "TOKEN: $TOKEN"

# URL encode the query
if [[ "$QUERY" == cpe* ]] || [[ "$QUERY" == purl* ]] || [[ "$QUERY" == name* ]]; then
    QUERY=$(echo "$QUERY" | jq -Rr @uri)
fi    
echo "QUERY: $QUERY"

# Build the final URL based on QUERY parameter
if [[ "$QUERY" == cpe* ]]; then
    FINAL_URL="$SERVER_URL$ENDPOINT/$QUERY$ADDITIONAL_PARAMETERS"
elif [[ "$QUERY" == purl* ]] || [[ "$QUERY" == name* ]]; then
    FINAL_URL="$SERVER_URL$ENDPOINT?q=$QUERY$ADDITIONAL_PARAMETERS"
else
    FINAL_URL="$SERVER_URL$ENDPOINT$QUERY$ADDITIONAL_PARAMETERS"
fi

echo "FINAL_URL: $FINAL_URL"

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/target"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Send the API request with Authorization header and save response
RESPONSE=$(curl --header "Authorization: Bearer ${TOKEN}" "$FINAL_URL" | jq '.')

# Display the response and save to file
echo "$RESPONSE"
echo "$RESPONSE" > "$TARGET_DIR/last-response.json"
