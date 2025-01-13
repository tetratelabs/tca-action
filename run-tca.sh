#!/bin/bash

# Debug function
debug() {
    if [[ "${RUNNER_DEBUG:-}" == "1" ]]; then
        echo "$@"
    fi
}

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Set workspace directory based on environment
WORKSPACE_DIR="${GITHUB_WORKSPACE:-$PWD}"

# Default values
OUTPUT_FILE="${1:-tca-output.txt}"
LOCAL_ONLY="${LOCAL_ONLY:-false}"
MESH_CONFIG="${MESH_CONFIG:-}"
KUBE_CONFIG="${KUBE_CONFIG:-}"

debug "Starting TCA analyzer..."
ARGS="--output-disabled-hyperlink=true"

debug "Initial ARGS: '$ARGS'"

# Clean up any existing output file
rm -f "$OUTPUT_FILE"
debug "Cleaned up existing output file"

if [[ "$LOCAL_ONLY" == "true" ]]; then
    ARGS="$ARGS --local-only"
    debug "Added local-only flag, ARGS now: '$ARGS'"
fi

if [[ -n "$MESH_CONFIG" ]]; then
    # Handle relative paths
    if [[ "$MESH_CONFIG" == ./* ]]; then
        MESH_CONFIG="$WORKSPACE_DIR/$MESH_CONFIG"
    fi
    ARGS="$ARGS -f $MESH_CONFIG"
    debug "Added mesh-config, ARGS now: '$ARGS'"
fi

if [[ -n "$KUBE_CONFIG" ]]; then
    # Handle relative paths
    if [[ "$KUBE_CONFIG" == ./* ]]; then
        KUBE_CONFIG="$WORKSPACE_DIR/$KUBE_CONFIG"
    fi
    if [[ -f "$KUBE_CONFIG" ]]; then
        ARGS="$ARGS -c $KUBE_CONFIG"
        debug "Added kubeconfig from $KUBE_CONFIG, ARGS now: '$ARGS'"
    else
        debug "Kubeconfig path specified but file not found at $KUBE_CONFIG"
    fi
else
    debug "No kubeconfig specified"
fi

set +e
# Run the TCA command
TCA_COMMAND="tca analyze $ARGS || true"
debug "Running TCA command: $TCA_COMMAND"
TMP_OUTPUT=$(mktemp)
eval $TCA_COMMAND > "$TMP_OUTPUT"
EXIT_CODE=$?  # Capture the exit code
set -e

# Log the exit code and continue
debug "TCA analysis completed with exit code $EXIT_CODE"
if [[ -n "$GITHUB_ENV" ]]; then
    echo "tca-exit-code=$EXIT_CODE" >> $GITHUB_ENV
fi
debug "TCA analysis completed"

# Show raw output in debug mode
if [[ "${RUNNER_DEBUG:-}" == "1" ]]; then
    debug "Raw TCA output:"
    cat "$TMP_OUTPUT"
fi

# Check if there are no issues
if grep -q "No issues found in Istio configuration" "$TMP_OUTPUT"; then
    echo "No issues found in Istio configuration"
    # Create output file with success message
    {
        echo "### Tetrate Config Analyzer Results"
        echo
        echo "✅ TCA analysis completed successfully with no issues"
        echo
        echo "No issues were found in the Istio configuration."
    } > "$OUTPUT_FILE"
    
    # Clean up and exit
    rm -f "$TMP_OUTPUT"
    exit $EXIT_CODE
fi

# Create FILTERED_OUTPUT file
FILTERED_OUTPUT=$(mktemp)
debug "Created temporary file for filtered output: $FILTERED_OUTPUT"

# Filter TCA output for matching names and namespaces
debug "Filtering TCA output"

# Determine which awk to use
if [[ "$(uname)" == "Darwin" ]]; then
    AWK_CMD="gawk"
else
    AWK_CMD="awk"
fi

# Extract names and namespaces from the mesh config
namespaces=""
if [[ -n "$MESH_CONFIG" ]]; then
    debug "Extracting names and namespaces from mesh config"
    
    namespaces=$($AWK_CMD '
        BEGIN { 
            RS="---"; 
            FS="\n";
            in_list = 0;
        }
        function clean_value(val) {
            # Remove quotes and trim spaces
            gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", val)
            gsub(/#.*$/, "", val)  # Remove comments
            return val
        }
        {
            # Skip empty documents
            if (NF <= 1) next
            
            # Reset variables for each document
            name=""; namespace=""; skip_doc=0;
            in_metadata=0;
            has_api_version=0;
            
            # First pass - check for apiVersion and items
            for (i=1; i<=NF; i++) {
                if ($i ~ /^apiVersion:/) {
                    has_api_version=1
                }
                if ($i ~ /^items:/) {
                    in_list = 1
                }
            }
            
            # Second pass - process metadata
            if (has_api_version || in_list) {
                for (i=1; i<=NF; i++) {
                    # Skip lines with templates
                    if ($i ~ /{{.*}}/) {
                        skip_doc = 1
                        next
                    }
                    
                    if ($i ~ /^[[:space:]]*metadata:/) {
                        in_metadata = 1
                        continue
                    }
                    
                    if (in_metadata) {
                        if ($i ~ /^[[:space:]]*name:/) {
                            name = clean_value(gensub(/^[[:space:]]*name:[ \t]*/, "", 1, $i))
                        }
                        if ($i ~ /^[[:space:]]*namespace:/) {
                            namespace = clean_value(gensub(/^[[:space:]]*namespace:[ \t]*/, "", 1, $i))
                        }
                        # Exit metadata section when we hit a non-indented line
                        if ($i !~ /^[[:space:]]/ && $i ~ /:/) {
                            in_metadata = 0
                        }
                    }
                }
                
                # Print only if we have valid name and namespace and its not a template
                if (name != "" && namespace != "" && !skip_doc) {
                    print name " " namespace
                }
            }
            
            # Reset list flag if not in a list
            if (!in_list) {
                in_list = 0
            }
        }
    ' "$MESH_CONFIG" | sort | uniq)

    debug "Extracted names and namespaces:"
    debug "$namespaces"
else
    debug "No mesh config provided"
fi

# Process rows based on mode
if [[ -z "$MESH_CONFIG" ]]; then
    # If no mesh config (fully remote mode), copy all rows without filtering
    debug "Remote mode: copying all rows without filtering"
    awk 'NR > 3' "$TMP_OUTPUT" > "$FILTERED_OUTPUT"
else
    # Iterate over the original rows in TMP_OUTPUT with filtering
    debug "Processing original rows with filtering"
    ROW_NUM=1
    awk 'NR > 3' "$TMP_OUTPUT" | while read -r row; do
        for line in $namespaces; do
            name=$(echo "$line" | awk '{print $1}')
            namespace=$(echo "$line" | awk '{print $2}')
            
            # Check if the row matches the current name and namespace
            if [[ "$row" == *"$name"* && "$row" == *"$namespace"* ]]; then
                # Remove any existing numbers and append the correct sequential number
                row_content=$(echo "$row" | sed 's/^│[[:space:]]*[0-9]*[[:space:]]*│//')
                printf "│%8d │%s\n" "$ROW_NUM" "$row_content"
                ROW_NUM=$((ROW_NUM + 1))
                break
            fi
        done
    done > "$FILTERED_OUTPUT"
fi

# Show filtered output in debug mode
if [[ "${RUNNER_DEBUG:-}" == "1" ]]; then
    debug "Filtered TCA output:"
    cat "$FILTERED_OUTPUT"
fi

# Calculate summary counts dynamically from the filtered table
debug "Calculating error and warning counts from the filtered table"
ERROR_COUNT=$(awk -F'│' '$0 ~ /error/ {count++} END {print count+0}' "$FILTERED_OUTPUT")
WARNING_COUNT=$(awk -F'│' '$0 ~ /warning/ {count++} END {print count+0}' "$FILTERED_OUTPUT")

if [[ -n "$GITHUB_ENV" ]]; then
    echo "error-count=$ERROR_COUNT" >> $GITHUB_ENV
    echo "warning-count=$WARNING_COUNT" >> $GITHUB_ENV
fi

# Debugging: Print calculated counts
debug "ERROR_COUNT=$ERROR_COUNT, WARNING_COUNT=$WARNING_COUNT"

# Create output file with updated summary and header
{
    echo "### Tetrate Config Analyzer Results"
    echo
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "❌ **Error:** TCA analysis found $ERROR_COUNT error(s)"
    fi
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo "⚠️ **Warning:** TCA analysis found $WARNING_COUNT warning(s)"
    fi
    if [ "$ERROR_COUNT" -eq 0 ] && [ "$WARNING_COUNT" -eq 0 ]; then
        echo "✅ TCA analysis completed successfully with no issues"
    fi
    echo
    echo "| NO. | SEVERITY | CODE    | KIND            | NAME                          | NAMESPACE     | DESCRIPTION                                                         |"
    echo "|-----|----------|---------|-----------------|-------------------------------|---------------|--------------------------------------------------------------------|"

    # Iterate over rows and add links to CODE column while preserving alignment
    NEW_ROW_NUM=1
    while read -r row; do
        # Extract and clean up individual columns
        severity=$(echo "$row" | awk -F'│' '{print $4}' | xargs)
        code=$(echo "$row" | awk -F'│' '{print $5}' | xargs)
        kind=$(echo "$row" | awk -F'│' '{print $6}' | xargs)
        name=$(echo "$row" | awk -F'│' '{print $7}' | xargs)
        namespace=$(echo "$row" | awk -F'│' '{print $8}' | xargs)
        description=$(echo "$row" | awk -F'│' '{print $9}' | xargs)

        # Create a Markdown link for the CODE column
        code_link="[${code}](https://docs.tetrate.io/istio-subscription/tools/tca/analysis/${code})"

        # Format the row as a Markdown table row
        printf "| %-3s | %-8s | %-7s | %-17s | %-30s | %-13s | %-67s |\n" \
            "$NEW_ROW_NUM" "$severity" "$code_link" "$kind" "$name" "$namespace" "$description"
        
        NEW_ROW_NUM=$((NEW_ROW_NUM + 1))
    done < "$FILTERED_OUTPUT"

} > "$OUTPUT_FILE"

# Clean up temporary files
debug "Cleaning up temporary files"
rm -f "$FILTERED_OUTPUT" "$TMP_OUTPUT"

exit $EXIT_CODE
