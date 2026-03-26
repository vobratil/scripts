#!/bin/bash

# Script to send an API request with Authorization header
# Usage: ./send-api-request.sh <SERVER_URL> <ENDPOINT> <QUERY> [GET_TOKEN_SCRIPT_PATH]

if [[ $# -lt 3 ]]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 <SERVER_URL> <ENDPOINT> <QUERY> [GET_TOKEN_SCRIPT_PATH]"
    exit 1
fi

SERVER_URL="$1"
ENDPOINT="$2"
QUERY="$3"
GET_TOKEN_SCRIPT_PATH="${4:-../../tpa-qe-ci/scripts/get-token.sh}"

# Check if required environment variables are defined
if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]]; then
    echo "Error: CLIENT_ID and/or CLIENT_SECRET environment variables are not defined"
    exit 1
fi

# Source the token script if it exists
if [[ -f "$GET_TOKEN_SCRIPT_PATH" ]]; then
    TOKEN=$(source "$GET_TOKEN_SCRIPT_PATH" "$SERVER_URL" "$CLIENT_ID" "$CLIENT_SECRET" 2>/dev/null | tail -n 1)
else
    echo "Warning: Token script not found at $GET_TOKEN_SCRIPT_PATH"
fi

# URL encode the query
QUERY=$(echo "$QUERY" | jq -Rr @uri)
echo "Encoded QUERY: $QUERY"

# Build the final URL based on QUERY parameter
if [[ "$QUERY" == cpe* ]]; then
    FINAL_URL="$SERVER_URL$ENDPOINT/$QUERY"
elif [[ "$QUERY" == purl* ]] || [[ "$QUERY" == name* ]]; then
    FINAL_URL="$SERVER_URL$ENDPOINT?q=$QUERY"
else
    FINAL_URL="$SERVER_URL$ENDPOINT$QUERY"
fi

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
