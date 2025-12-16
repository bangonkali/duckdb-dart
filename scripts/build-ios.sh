#!/bin/bash
# Build DuckDB native libraries for iOS
# Creates a universal XCFramework for devices and simulators
#
# This script builds a MONOLITHIC DuckDB library with ALL extensions statically linked:
#   - spatial (GIS/geometry functions via GDAL, GEOS, PROJ)
#   - vss (Vector Similarity Search with HNSW indexes)
#   - icu (International Components for Unicode)
#   - json (JSON parsing and generation)
#   - parquet (Parquet file format support)
#   - inet (IP address functions)
#   - tpch (TPC-H benchmark queries)
#   - tpcds (TPC-DS benchmark queries)
#
# Why monolithic? Mobile platforms (iOS) discourage dynamic loading.
# All functionality is available offline immediately after app install.
#
# Prerequisites:
#   - Xcode with command line tools
#   - vcpkg: git clone https://github.com/Microsoft/vcpkg.git && ./vcpkg/bootstrap-vcpkg.sh
#   - cmake, ninja, git
#
# Usage:
#   ./scripts/build-ios.sh              # Build XCFramework
#   ./scripts/build-ios.sh --build-app  # Also build example app (skipped for dart lib)

set -e

# Configuration
DUCKDB_VERSION="${DUCKDB_VERSION:-main}"
# All extensions - always included, statically linked
DUCKDB_EXTENSIONS="icu;json;parquet;inet;tpch;tpcds"
BUILD_APP=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/ios/Frameworks"

# vcpkg settings (required for spatial extension)
VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check for vcpkg (required)
check_vcpkg() {
    if [ ! -f "$VCPKG_ROOT/vcpkg" ]; then
        log_error "vcpkg not found at $VCPKG_ROOT"
        log_error "vcpkg is REQUIRED for building DuckDB with spatial extension"
        log_error ""
        log_error "Install vcpkg:"
        log_error "  git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg"
        log_error "  ~/vcpkg/bootstrap-vcpkg.sh"
        log_error "  export VCPKG_ROOT=\$HOME/vcpkg"
        exit 1
    fi
    log_info "Using vcpkg: $VCPKG_ROOT"
}

# Check for required tools
check_tools() {
    local missing_tools=()

    if ! command -v cmake &> /dev/null; then
        missing_tools+=("cmake")
    fi

    if ! command -v ninja &> /dev/null; then
        missing_tools+=("ninja")
    fi

    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v xcodebuild &> /dev/null; then
        missing_tools+=("xcode-select")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them: brew install cmake ninja git"
        exit 1
    fi
}

# Clone or update duckdb-spatial source
get_spatial_source() {
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    
    log_step "Getting duckdb-spatial source..."
    
    mkdir -p "${PROJECT_ROOT}/build/spatial"
    
    if [ -d "$spatial_dir" ]; then
        log_info "Using existing duckdb-spatial source..."
    else
        log_info "Cloning duckdb-spatial repository..."
        git clone --recurse-submodules https://github.com/duckdb/duckdb-spatial.git "$spatial_dir"
    fi
    
    # Use the duckdb submodule from spatial for consistency
    cd "$spatial_dir"
    git reset --hard
    git submodule update --init --recursive
}

# Clone or update duckdb-vss source
get_vss_source() {
    local vss_dir="${PROJECT_ROOT}/build/vss/duckdb-vss"
    
    log_step "Getting duckdb-vss source..."
    
    mkdir -p "${PROJECT_ROOT}/build/vss"
    
    if [ -d "$vss_dir" ]; then
        log_info "Using existing duckdb-vss source..."
        cd "$vss_dir"
        git reset --hard
        git fetch origin
        git pull
    else
        log_info "Cloning duckdb-vss repository..."
        git clone --recurse-submodules https://github.com/duckdb/duckdb-vss "$vss_dir"
    fi
}

# Clone or update duckpgq-extension source
get_duckpgq_source() {
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    local duckpgq_ref="v1.4-andium"  # track upstream branch
    
    log_step "Getting duckpgq-extension source..."
    
    mkdir -p "${PROJECT_ROOT}/build/duckpgq"
    
    if [ -d "$duckpgq_dir" ]; then
        log_info "Using existing duckpgq-extension source..."
        cd "$duckpgq_dir"
        git reset --hard
        git fetch origin "$duckpgq_ref"
        git checkout "$duckpgq_ref"
    else
        log_info "Cloning duckpgq-extension repository..."
        git clone --recurse-submodules -b "$duckpgq_ref" https://github.com/cwida/duckpgq-extension "$duckpgq_dir"
        cd "$duckpgq_dir"
    fi
    
    # Initialize duckpgq's duckdb submodule
    cd "$duckpgq_dir"
    
    # Force HTTPS for submodules
    if [ -f ".gitmodules" ]; then
        log_info "Switching submodule URLs from SSH to HTTPS..."
        sed -i.bak 's/git@github.com:/https:\/\/github.com\//g' .gitmodules
        git submodule sync
    fi
    
    git submodule update --init --recursive
}

# Create custom VSS extension config for static linking
create_vss_extension_config() {
    local config_dir="${PROJECT_ROOT}/build/vss"
    local config_file="${config_dir}/vss_extension_config.cmake"
    local vss_dir="${PROJECT_ROOT}/build/vss/duckdb-vss"
    
    log_info "Creating custom VSS extension config for static linking..."
    
    mkdir -p "$config_dir"
    
    cat > "$config_file" << EOF
# Custom VSS extension config for static linking
duckdb_extension_load(vss
    SOURCE_DIR ${vss_dir}
    LOAD_TESTS
)
EOF
    
    log_info "VSS extension config created at: $config_file"
}

# Create custom DuckPGQ extension config for static linking
create_duckpgq_extension_config() {
    local config_dir="${PROJECT_ROOT}/build/duckpgq"
    local config_file="${config_dir}/duckpgq_extension_config.cmake"
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    
    log_info "Creating custom DuckPGQ extension config for static linking..."
    
    mkdir -p "$config_dir"
    
    cat > "$config_file" << EOF
# Custom DuckPGQ extension config for static linking
duckdb_extension_load(duckpgq
    SOURCE_DIR ${duckpgq_dir}
    LOAD_TESTS
)
EOF
    
    log_info "DuckPGQ extension config created at: $config_file"
}

# Create custom triplets for iOS
create_custom_triplets() {
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local custom_triplets_dir="$spatial_dir/custom-triplets"
    local deployment_target="14.0"
    
    log_info "Creating custom iOS triplets with deployment target $deployment_target..."
    
    mkdir -p "$custom_triplets_dir"
    
    # arm64-ios (Device)
    cat > "$custom_triplets_dir/arm64-ios.cmake" << EOF
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_DEPLOYMENT_TARGET $deployment_target)
set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_OSX_DEPLOYMENT_TARGET=$deployment_target")
EOF

    # arm64-ios-simulator (Simulator on Apple Silicon)
    cat > "$custom_triplets_dir/arm64-ios-simulator.cmake" << EOF
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_DEPLOYMENT_TARGET $deployment_target)
set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_OSX_SYSROOT=iphonesimulator" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$deployment_target")
EOF

    # x64-ios-simulator (Simulator on Intel)
    cat > "$custom_triplets_dir/x64-ios-simulator.cmake" << EOF
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_DEPLOYMENT_TARGET $deployment_target)
set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_OSX_SYSROOT=iphonesimulator" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$deployment_target")
EOF

    log_info "Custom triplets created at $custom_triplets_dir"
}

# Install vcpkg dependencies for iOS
install_vcpkg_deps() {
    local triplet=$1
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local host_triplet
    
    # Detect host triplet for cross-compilation tools
    if [[ "$(uname -m)" == "arm64" ]]; then
        host_triplet="arm64-osx"
    else
        host_triplet="x64-osx"
    fi
    
    log_step "Installing vcpkg dependencies for $triplet (host: $host_triplet)..."
    log_info "This may take 30-60 minutes on first run (building GDAL, GEOS, PROJ from source)..."
    
    cd "$spatial_dir"
    
    # Backup original vcpkg.json
    if [ ! -f "$spatial_dir/vcpkg.json.original" ]; then
        cp "$spatial_dir/vcpkg.json" "$spatial_dir/vcpkg.json.original"
    fi
    
    # Restore original vcpkg.json
    cp "$spatial_dir/vcpkg.json.original" "$spatial_dir/vcpkg.json"
    
    # Create custom triplets
    create_custom_triplets
    local custom_triplets_dir="$spatial_dir/custom-triplets"
    
    # Install dependencies
    "$VCPKG_ROOT/vcpkg" install \
        --triplet="$triplet" \
        --host-triplet="$host_triplet" \
        --x-install-root="$spatial_dir/vcpkg_installed" \
        --overlay-triplets="$custom_triplets_dir"
    
    log_info "vcpkg dependencies installed for $triplet"
}

# Build DuckDB for a specific iOS platform
build_for_platform() {
    local platform=$1        # iphoneos or iphonesimulator
    local arch=$2            # arm64 or x86_64
    local triplet=$3         # vcpkg triplet
    local platform_name=$4   # for output naming
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    local build_path="$spatial_dir/build/${platform_name}"
    local vss_config="${PROJECT_ROOT}/build/vss/vss_extension_config.cmake"
    local duckpgq_config="${PROJECT_ROOT}/build/duckpgq/duckpgq_extension_config.cmake"
    
    log_step "Building DuckDB for ${platform} (${arch})..."
    
    # Install vcpkg dependencies
    install_vcpkg_deps "$triplet"
    
    cd "$spatial_dir"
    
    local vcpkg_installed="$spatial_dir/vcpkg_installed/$triplet"
    
    if [ ! -d "$vcpkg_installed" ]; then
        log_error "vcpkg installation not found at $vcpkg_installed"
        exit 1
    fi
    
    log_info "Using vcpkg libraries from: $vcpkg_installed"
    
    # Detect host triplet
    local host_triplet
    if [[ "$(uname -m)" == "arm64" ]]; then
        host_triplet="arm64-osx"
    else
        host_triplet="x64-osx"
    fi
    
    # Clean previous build
    rm -rf "$build_path"
    mkdir -p "$build_path"
    
    local sdk_path=$(xcrun --sdk "${platform}" --show-sdk-path)
    local deployment_target="14.0"
    
    log_info "Running CMake configuration..."
    
    local num_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    local system_name="iOS"
    local system_processor="$arch"
    if [[ "$arch" == "arm64" ]]; then
        system_processor="aarch64"
    fi
    
    local custom_triplets_dir="$spatial_dir/custom-triplets"

    cmake -G "Ninja" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
        -DVCPKG_TARGET_TRIPLET="$triplet" \
        -DVCPKG_HOST_TRIPLET="$host_triplet" \
        -DVCPKG_INSTALLED_DIR="$spatial_dir/vcpkg_installed" \
        -DVCPKG_OVERLAY_PORTS="$spatial_dir/vcpkg_ports" \
        -DVCPKG_OVERLAY_TRIPLETS="$custom_triplets_dir" \
        -DCMAKE_SYSTEM_NAME="$system_name" \
        -DCMAKE_SYSTEM_PROCESSOR="$system_processor" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DEXTENSION_STATIC_BUILD=ON \
        -DDUCKDB_EXTENSION_CONFIGS="$spatial_dir/extension_config.cmake;$vss_config;$duckpgq_config" \
        -DSPATIAL_USE_NETWORK=OFF \
        -DBUILD_SHELL=OFF \
        -DBUILD_UNITTESTS=OFF \
        -DENABLE_EXTENSION_AUTOLOADING=ON \
        -DENABLE_EXTENSION_AUTOINSTALL=OFF \
        -DDUCKDB_EXPLICIT_PLATFORM="$platform_name" \
        -DLOCAL_EXTENSION_REPO="" \
        -DOVERRIDE_GIT_DESCRIBE="" \
        -DBUILD_EXTENSIONS="$DUCKDB_EXTENSIONS" \
        -S "$duckpgq_dir/duckdb" \
        -B "$build_path"
    
    log_info "Building DuckDB..."
    cmake --build "$build_path" --config Release -- -j$num_cores
    
    if [ -f "$build_path/src/libduckdb.a" ]; then
        log_info "Built: $build_path/src/libduckdb.a"
    elif [ -f "$build_path/src/libduckdb_static.a" ]; then
        log_info "Found libduckdb_static.a, renaming to libduckdb.a..."
        cp "$build_path/src/libduckdb_static.a" "$build_path/src/libduckdb.a"
    else
        log_error "Build failed - libduckdb.a not found!"
        exit 1
    fi

    # Recursive Iterative merge
    log_info "Performing recursive iterative merge..."
    
    get_abs_path() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

    local core_lib=$(get_abs_path "$build_path/src/libduckdb.a")
    local extension_libs=$(find "$build_path/extension" -name "lib*_extension.a")
    local libs_to_merge=("$core_lib")
    
    log_info "  Adding extensions:"
    while IFS= read -r lib; do
        if [ -n "$lib" ]; then
            local abs_lib=$(get_abs_path "$lib")
            log_info "    + $(basename "$abs_lib")"
            libs_to_merge+=("$abs_lib")
        fi
    done <<< "$extension_libs"
    
    local iteration=1
    while true; do
        nm -gP "${libs_to_merge[@]}" > "$build_path/all_symbols.txt" 2>/dev/null
        awk '$2 ~ /[TDBR]/ {print $1}' "$build_path/all_symbols.txt" | sort -u > "$build_path/defined.txt"
        awk '$2 == "U" {print $1}' "$build_path/all_symbols.txt" | sort -u > "$build_path/undefined.txt"
        comm -23 "$build_path/undefined.txt" "$build_path/defined.txt" > "$build_path/needed.txt"
        
        local needed_count=$(wc -l < "$build_path/needed.txt")
        if [ $needed_count -eq 0 ]; then break; fi
        
        local third_party_libs=$(find "$build_path" "$vcpkg_installed/lib" -name "*.a" ! -name "libduckdb.a" ! -name "libduckdb_static.a" ! -name "libduckdb_merged.a" ! -name "lib*_extension.a")
        local added_in_this_round=0
        
        if [ -n "$third_party_libs" ]; then
            while IFS= read -r lib; do
                local lib_name=$(basename "$lib")
                local abs_lib=$(get_abs_path "$lib")
                
                local already_merged=false
                for merged in "${libs_to_merge[@]}"; do
                    if [ "$merged" == "$abs_lib" ]; then already_merged=true; break; fi
                done
                if [ "$already_merged" = true ]; then continue; fi
                
                nm -gP "$lib" 2>/dev/null | awk '$2 ~ /[TDBR]/ {print $1}' | sort -u > "$build_path/lib_defined.txt"
                if comm -12 "$build_path/needed.txt" "$build_path/lib_defined.txt" | grep -q .; then
                    log_info "    Adding $lib_name"
                    libs_to_merge+=("$abs_lib")
                    added_in_this_round=$((added_in_this_round + 1))
                    break 
                fi
            done <<< "$third_party_libs"
        fi
        
        if [ $added_in_this_round -eq 0 ]; then break; fi
        iteration=$((iteration + 1))
        if [ $iteration -gt 100 ]; then break; fi
    done
    
    log_info "Merging libraries..."
    libtool -static -o "$build_path/src/libduckdb_merged.a" "${libs_to_merge[@]}"
    mv "$build_path/src/libduckdb_merged.a" "$build_path/src/libduckdb.a"
    
    rm -f "$build_path/all_symbols.txt" "$build_path/defined.txt" "$build_path/undefined.txt" "$build_path/needed.txt" "$build_path/lib_defined.txt"
}

# Create fat library for multiple architectures
create_fat_library() {
    local output=$1
    shift
    local inputs=("$@")
    
    log_info "Creating fat library at $output..."
    mkdir -p "$(dirname "$output")"
    lipo -create "${inputs[@]}" -output "$output"
}

# Create XCFramework
create_xcframework() {
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local xcframework_path="${OUTPUT_DIR}/DuckDB.xcframework"
    
    log_step "Creating XCFramework..."
    
    rm -rf "$xcframework_path"
    
    mkdir -p "$spatial_dir/build/lib-device"
    mkdir -p "$spatial_dir/build/lib-simulator"
    
    local device_lib="$spatial_dir/build/ios_arm64/src/libduckdb.a"
    local sim_arm64="$spatial_dir/build/ios_arm64_simulator/src/libduckdb.a"
    local sim_x64="$spatial_dir/build/ios_x64_simulator/src/libduckdb.a"
    local sim_fat="$spatial_dir/build/lib-simulator/libduckdb.a"
    
    create_fat_library "$sim_fat" "$sim_arm64" "$sim_x64"
    
    xcodebuild -create-xcframework \
        -library "$device_lib" \
        -library "$sim_fat" \
        -output "$xcframework_path"
    
    log_info "XCFramework created at: $xcframework_path"
}

# Copy DuckDB headers to XCFramework
copy_headers() {
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    local xcframework_path="${OUTPUT_DIR}/DuckDB.xcframework"
    local src_include_dir="${duckpgq_dir}/duckdb/src/include"
    
    log_info "Copying DuckDB headers..."
    
    for platform_dir in "$xcframework_path"/*; do
        if [ -d "$platform_dir" ]; then
            local headers_dir="$platform_dir/Headers"
            mkdir -p "$headers_dir"
            cp -R "$src_include_dir"/* "$headers_dir/"
            log_info "Headers copied to $headers_dir"
        fi
    done
}

# Verify extensions are statically linked
verify_extensions() {
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local lib_path="$spatial_dir/build/ios_arm64/src/libduckdb.a"
    
    log_step "Verifying extensions are statically linked..."
    
    if [ ! -f "$lib_path" ]; then
        log_warn "Library not found for verification"
        return
    fi
    
    if nm "$lib_path" 2>/dev/null | grep -q "SpatialExtension"; then
        log_info "  ✓ Spatial extension found"
    else
        log_warn "  ✗ Spatial extension MISSING"
    fi
}

main() {
    log_info "=== DuckDB iOS Build Script (Monolithic) ==="
    
    check_tools
    check_vcpkg
    
    get_spatial_source
    get_vss_source
    get_duckpgq_source
    create_vss_extension_config
    create_duckpgq_extension_config
    
    # Build for all iOS platforms
    build_for_platform "iphoneos" "arm64" "arm64-ios" "ios_arm64"
    build_for_platform "iphonesimulator" "arm64" "arm64-ios-simulator" "ios_arm64_simulator"
    build_for_platform "iphonesimulator" "x86_64" "x64-ios-simulator" "ios_x64_simulator"
    
    create_xcframework
    copy_headers
    verify_extensions
    
    log_info "=== Build complete! ==="
    log_info "Output: ${OUTPUT_DIR}/DuckDB.xcframework"
}

main
