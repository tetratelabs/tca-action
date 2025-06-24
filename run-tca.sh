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
    # Handle both space-separated and newline-separated lists
    # Convert newlines to spaces and split into array
    IFS=' ' read -r -a config_files <<< "${MESH_CONFIG//$'\n'/ }"
    
    for config_file in "${config_files[@]}"; do
        # Trim whitespace
        config_file="${config_file## }"
        config_file="${config_file%% }"
        
        if [[ -n "$config_file" ]]; then
            # Handle relative paths
            if [[ "$config_file" == ./* ]]; then
                config_file="$WORKSPACE_DIR/$config_file"
            fi
            
            # Check if file exists
            if [[ -f "$config_file" ]]; then
                valid_config_files+=("$config_file")
                ARGS="$ARGS -f $config_file"
                debug "Added mesh-config file: $config_file, ARGS now: '$ARGS'"
            else
                debug "Skipping non-existent file: $config_file"
                echo "Warning: Config file not found: $config_file"
            fi
        fi
    done

    # Exit if no valid config files found when mesh config is specified
    if [[ ${#valid_config_files[@]} -eq 0 && -n "$MESH_CONFIG" ]]; then
        echo "Error: No valid configuration files found"
        exit 1
    fi
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
TCA_COMMAND="tca analyze $ARGS"
debug "Running TCA command: $TCA_COMMAND"
TMP_OUTPUT=$(mktemp)
TMP_ERROR=$(mktemp)
eval $TCA_COMMAND > "$TMP_OUTPUT" 2> "$TMP_ERROR"
EXIT_CODE=$?  # Capture the exit code
set -e

# Return if $TMP_ERROR is not empty
if grep -v "Error: issues found in Istio configuration" "$TMP_ERROR"; then
    cat "$TMP_ERROR"
    cat grep -v "Error: issues found in Istio configuration" "$TMP_ERROR" >> $OUTPUT_FILE
    exit $EXIT_CODE
fi

# Check for specific error conditions
if [[ "$LOCAL_ONLY" == "true" ]] && grep -q "istiod deployment not found" "$TMP_ERROR"; then
    echo "Error: Local mode requires Istiod deployment configuration."
    echo "Please ensure your mesh-config includes:"
    echo "  - Istiod deployment"
    echo "  - Istio mesh-config configmap"
    echo "  - Istio secrets"
    rm -f "$TMP_OUTPUT" "$TMP_ERROR"
    exit 1
fi

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
    debug "Raw TCA error output:"
    cat "$TMP_ERROR"
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
    } >> "$OUTPUT_FILE"
    
    # Clean up and exit
    rm -f "$TMP_OUTPUT"
    exit $EXIT_CODE
fi

# Create FILTERED_OUTPUT file
FILTERED_OUTPUT=$(mktemp)
debug "Created temporary file for filtered output: $FILTERED_OUTPUT"

# Filter TCA output for matching names and namespaces
debug "Filtering TCA output"

# Extract names and namespaces from all mesh config files
namespaces=""
if [[ -n "$MESH_CONFIG" ]]; then
    debug "Extracting names and namespaces from mesh config files"
    
    TEMP_NS_FILE=$(mktemp)
    # Check if yq exists
    if ! command -v yq &> /dev/null; then
        debug "yq could not be found"
        echo "Error: yq is required but not installed"
        exit 1
    fi
    debug "yq version: $(yq --version)"
    
    for config_file in "${valid_config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            debug "Processing file: $config_file"
            
            # Process both standalone resources and items in List resources
            output=$(yq e '
                # Process items in List resources
                select(.kind == "List") | .items[] | 
                select(.metadata.name != null and .metadata.namespace != null) |
                .metadata.name + " " + .metadata.namespace
                
                # Process standalone resources
                , select(.kind != "List" and .metadata.name != null and .metadata.namespace != null) |
                .metadata.name + " " + .metadata.namespace
            ' "$config_file" 2>&1) || true
            
            if [[ -n "$output" ]]; then
                echo "$output" >> "$TEMP_NS_FILE"
            fi
        else
            debug "File not found or not readable: $config_file"
        fi
    done
    
    if [[ -f "$TEMP_NS_FILE" ]]; then
        sort -u "$TEMP_NS_FILE" -o "$TEMP_NS_FILE"
    else
        debug "No temp file created - no valid entries found"
    fi
    
    namespaces=$(cat "$TEMP_NS_FILE")
    rm -f "$TEMP_NS_FILE"

    debug "Extracted names and namespaces:"
    debug "$namespaces"
else
    debug "No mesh config provided"
fi

# Process rows based on mode
if [[ -z "$MESH_CONFIG" ]]; then
    # If no mesh config (fully remote mode), copy only content rows without borders and summary
    debug "Remote mode: copying content rows without table formatting"
    awk -F'│' '
        # Skip header, borders, and summary rows
        $0 !~ /^[├└─┌┐┘┍┑┕┙┝┥]+/ && 
        $0 !~ /SUMMARY/ && 
        NF > 3 {
            # Clean and print content rows
            gsub(/^[ \t]+|[ \t]+$/, "", $0)
            if (NR > 3) print
        }
    ' "$TMP_OUTPUT" > "$FILTERED_OUTPUT"
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

} >> "$OUTPUT_FILE"

# Clean up temporary files
debug "Cleaning up temporary files"
rm -f "$FILTERED_OUTPUT" "$TMP_OUTPUT" "$TMP_ERROR"

exit $EXIT_CODE
