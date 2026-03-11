#!/bin/bash

# This script retrieves all relevant SBOMs for a given product CPE, latest or non-latest.
# We can use this to get the entire SBOM tree from an instance.

# Parameterizable values
api_token=${1}
server_url=${2}
product_cpe=${3}
no_of_descendants=${4:-10}

# Validate required parameters
if [[ -z "$api_token" || -z "$server_url" || -z "$product_cpe" ]]; then
    echo "Usage: $0 <api_token> <server_url> <product_cpe> [no_of_descendants]"
    echo ""
    echo "Parameters:"
    echo "  api_token          - API authentication token"
    echo "  server_url         - Server URL (e.g., https://example.com)"
    echo "  product_cpe        - Product CPE identifier"
    echo "  no_of_descendants  - Number of descendants (optional, default: 10)"
    exit 1
fi

# Get the directory where the script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${script_dir}/target"

# Create target directory if it doesn't exist
mkdir -p "$target_dir"

# Phase 1: Make API call
api_response=$(curl -k --header "Authorization: ${api_token}" \
    ${server_url}/api/v2/analysis/component/${product_cpe}?descendants=${no_of_descendants})

# Phase 2: Format response as JSON
formatted_json=$(echo "$api_response" | jq '.')

# Phase 3: Extract lines containing sbom_id
sbom_id_lines=$(echo "$formatted_json" | grep 'sbom_id')

# Phase 4: Remove sbom_id string from lines
without_label=$(echo "$sbom_id_lines" | sed 's/sbom_id//g')

# Phase 5: Remove all characters except letters, numbers, and dashes
cleaned=$(echo "$without_label" | sed 's/[^a-zA-Z0-9-]//g')

# Phase 6: Sort and get unique values
unique_sbom_ids=$(echo "$cleaned" | sort | uniq)

# Phase 7: Download each SBOM document
echo "${unique_sbom_ids}" | while read sbom_id; do
    # Skip empty lines
    [[ -z "$sbom_id" ]] && continue
    
    # Create output filename based on sbom_id
    output_file="${target_dir}/${sbom_id}.json"
    
    # Download the document for this sbom_id
    echo "Downloading SBOM for: $sbom_id"
    curl -k --header "Authorization: ${api_token}" -s -o "${output_file}" \
        -w "HTTP Status: %{http_code}\n" \
        "${server_url}/api/v2/sbom/urn%3Auuid%3A${sbom_id}/download"

    # sleep 0.5
done

