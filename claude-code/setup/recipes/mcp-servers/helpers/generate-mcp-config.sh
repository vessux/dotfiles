#!/bin/bash

# MCP Configuration Generator
# Generates mcp.json from catalog and selected servers using yq (kislyuk/yq version)

set -euo pipefail

# Arguments
CATALOG_FILE="$1"
SELECTED_SERVERS="$2"
OUTPUT_FILE="$3"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install it:" >&2
    echo "  - pip install yq" >&2
    echo "  - or brew install python-yq" >&2
    exit 1
fi

# Validate inputs
if [ ! -f "$CATALOG_FILE" ]; then
    echo "Error: Catalog file not found: $CATALOG_FILE" >&2
    exit 1
fi

if [ -z "$SELECTED_SERVERS" ]; then
    echo "Error: No servers selected" >&2
    exit 1
fi

# Parse selected servers (comma-separated)
IFS=',' read -ra SERVERS <<< "$SELECTED_SERVERS"

# Start with empty JSON object
echo '{"mcpServers": {}}' > "$OUTPUT_FILE"

# Add each selected server to the configuration
for server in "${SERVERS[@]}"; do
    server=$(echo "$server" | xargs)  # trim whitespace
    
    # Skip empty entries
    [ -z "$server" ] && continue
    
    # Extract server config from catalog (remove name and description)
    # Using kislyuk/yq syntax which works with jq filters
    server_config=$(yq -r ".mcp_servers.\"$server\" | del(.name, .description)" "$CATALOG_FILE")
    
    # Add the server config to the output file
    temp_file="${OUTPUT_FILE}.tmp"
    jq --arg server "$server" --argjson config "$server_config" '.mcpServers[$server] = $config' "$OUTPUT_FILE" > "$temp_file" && mv "$temp_file" "$OUTPUT_FILE"
done

echo "Generated MCP configuration at: $OUTPUT_FILE"
echo "Selected servers: $SELECTED_SERVERS"