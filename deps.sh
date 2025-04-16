#!/usr/bin/env bash
# Save as generate-deps-graph.sh

# Get the package path
PACKAGE_PATH="$1"
OUTPUT_FILE="${2:-dependency-graph.json}"

echo "Analyzing dependencies for $PACKAGE_PATH..."

# Create a temporary directory for our work
TEMP_DIR=$(mktemp -d)
DEPS_LIST="$TEMP_DIR/deps-list.txt"
SIZES_LIST="$TEMP_DIR/sizes-list.txt"
REFS_DIR="$TEMP_DIR/refs"

mkdir -p "$REFS_DIR"

# Get all runtime dependencies
echo "Collecting dependencies..."
nix-store -q --requisites "$PACKAGE_PATH" > "$DEPS_LIST"

# Get sizes for all dependencies
echo "Collecting sizes..."
> "$SIZES_LIST"
while read -r dep; do
  size=$(nix-store --query --size "$dep")
  echo "$dep $size" >> "$SIZES_LIST"
done < "$DEPS_LIST"

# For each dependency, get its direct references
echo "Building dependency tree..."
while read -r dep; do
  nix-store -q --references "$dep" > "$REFS_DIR/$(basename "$dep")"
done < "$DEPS_LIST"

# Now build the JSON
echo "Generating JSON..."
echo "{" > "$OUTPUT_FILE"
echo "  \"name\": \"$(basename "$PACKAGE_PATH")\","  >> "$OUTPUT_FILE"
echo "  \"path\": \"$PACKAGE_PATH\"," >> "$OUTPUT_FILE"

# Get the size of the root package
ROOT_SIZE=$(grep "$PACKAGE_PATH" "$SIZES_LIST" | awk '{print $2}')
echo "  \"size\": $ROOT_SIZE," >> "$OUTPUT_FILE"
echo "  \"children\": [" >> "$OUTPUT_FILE"

# Process all direct dependencies of the root
DIRECT_DEPS=$(cat "$REFS_DIR/$(basename "$PACKAGE_PATH")")
FIRST=true

process_dependencies() {
  local parent="$1"
  local indent="$2"
  local direct_deps=$(cat "$REFS_DIR/$(basename "$parent")" 2>/dev/null || echo "")
  
  local first_child=true
  for dep in $direct_deps; do
    # Skip if this dep is not in our requisites list (it might be a runtime dep)
    if ! grep -q "$dep" "$DEPS_LIST"; then
      continue
    fi
    
    # Check if we've already processed this dep to avoid cycles
    if [[ "$processed_deps" == *"$dep"* ]]; then
      continue
    fi
    processed_deps="$processed_deps $dep"
    
    # Get size
    local size=$(grep "$dep" "$SIZES_LIST" | awk '{print $2}')
    
    if [[ "$first_child" != "true" ]]; then
      echo "," >> "$OUTPUT_FILE"
    fi
    first_child=false
    
    echo "$indent{" >> "$OUTPUT_FILE"
    echo "$indent  \"name\": \"$(basename "$dep")\"," >> "$OUTPUT_FILE"
    echo "$indent  \"path\": \"$dep\"," >> "$OUTPUT_FILE"
    echo "$indent  \"size\": $size," >> "$OUTPUT_FILE"
    
    # Check if this dep has children
    if [[ -f "$REFS_DIR/$(basename "$dep")" ]] && [[ -s "$REFS_DIR/$(basename "$dep")" ]]; then
      echo "$indent  \"children\": [" >> "$OUTPUT_FILE"
      process_dependencies "$dep" "$indent    "
      echo "$indent  ]" >> "$OUTPUT_FILE"
    else
      echo "$indent  \"children\": []" >> "$OUTPUT_FILE"
    fi
    
    echo -n "$indent}" >> "$OUTPUT_FILE"
  done
}

# Track processed deps to avoid cycles
processed_deps=""

process_dependencies "$PACKAGE_PATH" "    "

echo "" >> "$OUTPUT_FILE"
echo "  ]" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

echo "Dependency graph written to $OUTPUT_FILE"
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
