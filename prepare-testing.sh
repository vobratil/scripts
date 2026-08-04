#!/bin/bash

# Usage: source ./prepare-testing.sh [SERVER_URL] [CONSOLE_PASSWORD] [-o]

get_client_id_and_secret() {
    OIDC_RAW=$(oc get secret oidc-cli -o json 2>&1)
    if echo "$OIDC_RAW" | grep -q 'Error from server (NotFound): secrets "oidc-cli" not found'; then
        OIDC_OUTPUT="$OIDC_RAW"
    else
        OIDC_OUTPUT=$(echo "$OIDC_RAW" | jq -r '.data | to_entries | map( (.key|sub("[.-]"; "_")) + "=" + (.value | @base64d) )[]')
    fi
    if echo "$OIDC_OUTPUT" | grep -q 'Error from server (NotFound): secrets "oidc-cli" not found'; then
        echo "oidc-cli secret not found in OpenShift. Attempting to discover credentials from AWS Cognito..."

        AWS_REGIONS=$(aws ec2 describe-regions --region us-east-1 --query 'Regions[].RegionName' --output text 2>/dev/null)
        if [[ -z "$AWS_REGIONS" ]]; then
            echo "Error: Could not retrieve AWS regions. Ensure the aws CLI is configured correctly."
            OIDC_OUTPUT=""
        else
            COGNITO_POOL_ID=""
            COGNITO_REGION=""

            for REGION in $AWS_REGIONS; do
                POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "$REGION" \
                    --query "UserPools[?contains(Name, '${PROJECT}')].Id" --output text 2>/dev/null)
                if [[ -n "$POOL_ID" ]] && [[ "$POOL_ID" != "None" ]]; then
                    COGNITO_POOL_ID="$POOL_ID"
                    COGNITO_REGION="$REGION"
                    break
                fi
            done

            if [[ -z "$COGNITO_POOL_ID" ]]; then
                echo "Error: Could not find a Cognito user pool matching project '${PROJECT}' in any AWS region."
                OIDC_OUTPUT=""
            else
                echo "Found Cognito user pool '${COGNITO_POOL_ID}' in region '${COGNITO_REGION}'."

                CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
                    --user-pool-id "$COGNITO_POOL_ID" --region "$COGNITO_REGION" \
                    --query 'UserPoolClients[0].ClientId' --output text 2>/dev/null)
                if [[ -z "$CLIENT_ID" ]] || [[ "$CLIENT_ID" == "None" ]]; then
                    echo "Error: Could not find any app clients in user pool '${COGNITO_POOL_ID}'."
                    OIDC_OUTPUT=""
                else
                    CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
                        --user-pool-id "$COGNITO_POOL_ID" --client-id "$CLIENT_ID" \
                        --region "$COGNITO_REGION" \
                        --query 'UserPoolClient.ClientSecret' --output text 2>/dev/null)
                    if [[ -z "$CLIENT_SECRET" ]] || [[ "$CLIENT_SECRET" == "None" ]]; then
                        echo "Error: Could not retrieve the client secret for client '${CLIENT_ID}'."
                        OIDC_OUTPUT=""
                    else
                        OIDC_OUTPUT="client_id=${CLIENT_ID}"$'\n'"client_secret=${CLIENT_SECRET}"
                    fi
                fi
            fi
        fi
    fi
}

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

# Only get the OIDC client and secret if SERVER_URL is set and CONSOLE_PASSWORD is provided
if [[ $# -gt 1 ]]; then

    # Get API URL from SERVER_URL
    API_URL="${SERVER_URL#https://}"
    API_URL="${API_URL%/*}" # Remove everything after last slash
    API_URL="${API_URL/*apps/api}" # Replace 'apps' and everything left of it with 'api'
    API_URL="${API_URL}:6443" # Add port 6443
    # echo "API_URL: $API_URL"

    # Get project from SERVER_URL
    # Extract the part after 'server-' and remove everything after the next dot
    PROJECT="${SERVER_URL#*server-}" # Remove everything up to and including 'server-'
    PROJECT="${PROJECT%%.*}" # Remove everything from the next dot onward

    # Attempt to get the OIDC client and secret from the OpenShift cluster.
    # If this fails, attempt to get the OIDC client and secret from AWS Cognito.
    oc login "$API_URL" -u kubeadmin -p "$CONSOLE_PASSWORD" --insecure-skip-tls-verify=true 2>/dev/null
    oc project "$PROJECT" 2>/dev/null
    get_client_id_and_secret
fi

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
