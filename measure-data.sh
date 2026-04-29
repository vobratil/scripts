#!/bin/bash

# This script simply measures the volume of data on a TPA instance and logs it to a CSV file for monitoring purposes.

# Phase 1: Argument parsing
SERVER_URL="https://atlas.release.devshift.net"
API_TOKEN=""
INPUT_OUTPUT_FILE=""
TOKEN_SCRIPT_PATH="../reproducers/get-atlas-token.sh"

while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            SERVER_URL="$2"
            shift 2
            ;;
        --token)
            API_TOKEN="$2"
            shift 2
            ;;
        --token-script)
            TOKEN_SCRIPT_PATH="$2"
            shift 2
            ;;
        --file)
            INPUT_OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate mandatory arguments
if [[ -z "$INPUT_OUTPUT_FILE" ]]; then
    echo "Error: --file is required"
    exit 1
fi

# Function to obtain API token from script
obtain_token() {
    if [[ "$SERVER_URL" == *"atlas"* ]]; then
        echo "Obtaining API token from script: $TOKEN_SCRIPT_PATH"
        if [[ ! -f "$TOKEN_SCRIPT_PATH" ]]; then
            echo "Error: Token script '$TOKEN_SCRIPT_PATH' does not exist"
            exit 1
        fi
        API_TOKEN=$(bash "$TOKEN_SCRIPT_PATH" 2>/dev/null | tail -n1)
        if [[ -z "$API_TOKEN" ]]; then
            echo "Error: Failed to obtain API token from script"
            exit 1
        fi
        echo "API token obtained successfully"
    fi
}

# Obtain token if SERVER_URL contains "atlas" and token not provided
if [[ -z "$API_TOKEN" ]]; then
    obtain_token
fi

# Display collected data for verification
echo "SERVER_URL: $SERVER_URL"
echo "API_TOKEN: $API_TOKEN"
echo "INPUT_OUTPUT_FILE: $INPUT_OUTPUT_FILE"

# Phase 2: CSV validation and processing
# Check if file exists
if [[ ! -f "$INPUT_OUTPUT_FILE" ]]; then
    echo "Error: File '$INPUT_OUTPUT_FILE' does not exist"
    exit 1
fi

# Check if file is a CSV (basic check for .csv extension)
if [[ ! "$INPUT_OUTPUT_FILE" =~ \.csv$ ]]; then
    echo "Error: File '$INPUT_OUTPUT_FILE' is not a CSV file"
    exit 1
fi

# Collect all strings from the first column, starting from the second row
PRODUCT_CPES=()
while IFS=, read -r first_col rest; do
    # Skip empty lines
    [[ -z "$first_col" ]] && continue
    PRODUCT_CPES+=("$first_col")
done < <(tail -n +2 "$INPUT_OUTPUT_FILE")

echo ""
echo "Number of product CPEs collected: ${#PRODUCT_CPES[@]}"
echo ""
echo "Product CPEs:"
printf '%s\n' "${PRODUCT_CPES[@]}"

# Phase 3: Get the amount of SBOMs for each CPE
echo ""
echo "Collecting SBOM amounts from CPEs..."

# Add current date/time to the first line of the first empty column
current_datetime=$(date '+%Y-%m-%d %H:%M:%S')
awk -v datetime="$current_datetime" 'NR==1 {print $0 "," datetime; next} {print}' "$INPUT_OUTPUT_FILE" > "${INPUT_OUTPUT_FILE}.tmp" && mv "${INPUT_OUTPUT_FILE}.tmp" "$INPUT_OUTPUT_FILE"
echo "Added column with timestamp: $current_datetime"

total_cpes=${#PRODUCT_CPES[@]}
current_index=0
for cpe in "${PRODUCT_CPES[@]}"; do
    ((current_index++))
    # URL encode the CPE
    encoded_cpe=$(printf '%s' "$cpe" | jq -sRr @uri)

    # Calculate progress percentage
    progress_percent=$((current_index * 100 / total_cpes))

    echo "Processing: $cpe [$current_index/$total_cpes - $progress_percent%]"

    # Make API call (with retry on 401)
    retry_count=0
    max_retries=1
    while true; do
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "${SERVER_URL}/api/v2/analysis/component/${encoded_cpe}")

        # Extract HTTP status code (last line)
        http_code=$(echo "$response" | tail -n1)
        # Extract response body (all lines except last)
        response_body=$(echo "$response" | head -n -1)

        # Check if 401 (Unauthorized) and retry limit not reached
        if [[ "$http_code" == "401" ]] && [[ $retry_count -lt $max_retries ]]; then
            echo "  ⚠ Received 401 Unauthorized, re-obtaining API token."
            obtain_token
            ((retry_count++))
            continue
        fi

        # Exit loop if not 401 or retry limit reached
        break
    done

    # Check if successful (2xx status codes)
    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        echo "  ╳ Error (HTTP $http_code): API call failed for CPE '$cpe'"
        echo "Response: $response_body"
        exit 1
    fi

    # Parse JSON and extract "total" value
    total_value=$(echo "$response_body" | jq -r '.total')

    # Write total_value to the CSV file at the current row
    row_number=$((current_index + 1))
    awk -v row="$row_number" -v value="$total_value" 'NR==row {print $0 "," value; next} {print}' "$INPUT_OUTPUT_FILE" > "${INPUT_OUTPUT_FILE}.tmp" && mv "${INPUT_OUTPUT_FILE}.tmp" "$INPUT_OUTPUT_FILE"

    echo "  ✓ Success (HTTP $http_code), total number of SBOMs for this CPE: $total_value"
done

echo ""
echo "All CPEs processed successfully!"
