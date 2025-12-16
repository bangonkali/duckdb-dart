#!/bin/bash
# Build DuckDB native libraries for Android
# Supports arm64-v8a and x86_64 ABIs
#
# This script builds a MONOLITHIC DuckDB library with ALL extensions statically linked:
#   - spatial, vss, duckpgq, icu, json, parquet, inet, tpch, tpcds
#
# Prerequisites:
#   - Android NDK (via Android Studio)
#   - vcpkg: git clone https://github.com/Microsoft/vcpkg.git && ./vcpkg/bootstrap-vcpkg.sh
#   - cmake, ninja, git

set -e

# Configuration
DUCKDB_VERSION="${DUCKDB_VERSION:-main}"
DUCKDB_EXTENSIONS="icu;json;parquet;inet;tpch;tpcds"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/android/src/main"
VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-28}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_vcpkg() {
    if [ ! -f "$VCPKG_ROOT/vcpkg" ]; then
        log_error "vcpkg not found at $VCPKG_ROOT"
        exit 1
    fi
    log_info "Using vcpkg: $VCPKG_ROOT"
}

check_ndk() {
    if [ -z "$ANDROID_NDK" ]; then
        if [ -n "$ANDROID_HOME" ]; then
            NDK_DIR="$ANDROID_HOME/ndk"
            if [ -d "$NDK_DIR" ]; then
                ANDROID_NDK=$(ls -d "$NDK_DIR"/*/ 2>/dev/null | sort -V | tail -1)
                ANDROID_NDK="${ANDROID_NDK%/}"
            fi
        fi
        if [ -z "$ANDROID_NDK" ] && [ -d "$HOME/Library/Android/sdk/ndk" ]; then
            ANDROID_NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
            ANDROID_NDK="${ANDROID_NDK%/}"
        fi
    fi

    if [ -z "$ANDROID_NDK" ] || [ ! -d "$ANDROID_NDK" ]; then
        log_error "Android NDK not found!"
        exit 1
    fi
    log_info "Using Android NDK: $ANDROID_NDK"
}

check_tools() {
    if ! command -v cmake &> /dev/null; then log_error "cmake missing"; exit 1; fi
    if ! command -v ninja &> /dev/null; then log_error "ninja missing"; exit 1; fi
    if ! command -v git &> /dev/null; then log_error "git missing"; exit 1; fi
}

get_spatial_source() {
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    log_step "Getting duckdb-spatial source..."
    mkdir -p "${PROJECT_ROOT}/build/spatial"
    if [ ! -d "$spatial_dir" ]; then
        git clone --recurse-submodules https://github.com/duckdb/duckdb-spatial.git "$spatial_dir"
    fi
    cd "$spatial_dir"
    git reset --hard
    git submodule update --init --recursive
}

get_vss_source() {
    local vss_dir="${PROJECT_ROOT}/build/vss/duckdb-vss"
    log_step "Getting duckdb-vss source..."
    mkdir -p "${PROJECT_ROOT}/build/vss"
    if [ ! -d "$vss_dir" ]; then
        git clone --recurse-submodules https://github.com/duckdb/duckdb-vss "$vss_dir"
    else
        cd "$vss_dir"
        git reset --hard
        git fetch origin
        git pull
    fi
}

get_duckpgq_source() {
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    log_step "Getting duckpgq-extension source..."
    mkdir -p "${PROJECT_ROOT}/build/duckpgq"
    if [ ! -d "$duckpgq_dir" ]; then
        git clone --recurse-submodules -b v1.4-andium https://github.com/cwida/duckpgq-extension "$duckpgq_dir"
    else
        cd "$duckpgq_dir"
        git reset --hard
        git fetch origin v1.4-andium
        git checkout v1.4-andium
    fi
    cd "$duckpgq_dir"
    if [ -f ".gitmodules" ]; then
        sed -i.bak 's/git@github.com:/https:\/\/github.com\//g' .gitmodules
        git submodule sync
    fi
    git submodule update --init --recursive
}

create_vss_extension_config() {
    local config_dir="${PROJECT_ROOT}/build/vss"
    local config_file="${config_dir}/vss_extension_config.cmake"
    local vss_dir="${PROJECT_ROOT}/build/vss/duckdb-vss"
    mkdir -p "$config_dir"
    cat > "$config_file" << EOF
duckdb_extension_load(vss SOURCE_DIR ${vss_dir} LOAD_TESTS)
EOF
}

create_duckpgq_extension_config() {
    local config_dir="${PROJECT_ROOT}/build/duckpgq"
    local config_file="${config_dir}/duckpgq_extension_config.cmake"
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    mkdir -p "$config_dir"
    cat > "$config_file" << EOF
duckdb_extension_load(duckpgq SOURCE_DIR ${duckpgq_dir} LOAD_TESTS)
EOF
}

install_vcpkg_deps() {
    local triplet=$1
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local host_triplet
    
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then host_triplet="arm64-osx"; else host_triplet="x64-osx"; fi
    else
        host_triplet="x64-linux"
    fi
    
    log_step "Installing vcpkg dependencies for $triplet..."
    
    cd "$spatial_dir"
    if [ ! -f "$spatial_dir/vcpkg.json.original" ]; then
        cp "$spatial_dir/vcpkg.json" "$spatial_dir/vcpkg.json.original"
    fi
    
    cat > "$spatial_dir/vcpkg.json" << 'EOF'
{
  "dependencies": [
    "vcpkg-cmake", "openssl", "zlib", "geos", "expat",
    { "name": "sqlite3", "features": ["rtree"], "default-features": false },
    { "name": "proj", "default-features": false, "version>=": "9.1.1" },
    { "name": "curl", "features": ["openssl"], "default-features": false },
    { "name": "gdal", "version>=": "3.8.5", "features": ["network", "geos"] }
  ],
  "vcpkg-configuration": {
    "overlay-ports": [ "./vcpkg_ports" ],
    "registries": [
      { "kind": "git", "repository": "https://github.com/duckdb/vcpkg-duckdb-ports", "baseline": "3c7b96fa186c27eae2226a1b5b292f2b2dd3cf8f", "packages": [ "vcpkg-cmake" ] }
    ]
  },
  "builtin-baseline" : "ce613c41372b23b1f51333815feb3edd87ef8a8b"
}
EOF
    
    export ANDROID_NDK_HOME="$ANDROID_NDK"
    local custom_triplets_dir="$spatial_dir/custom-triplets"
    mkdir -p "$custom_triplets_dir"
    
    cat > "$custom_triplets_dir/arm64-android.cmake" << EOF
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION $ANDROID_API_LEVEL)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
EOF

    cat > "$custom_triplets_dir/x64-android.cmake" << EOF
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION $ANDROID_API_LEVEL)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=x86_64-linux-android")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=x86_64)
EOF

    "$VCPKG_ROOT/vcpkg" install --triplet="$triplet" --host-triplet="$host_triplet" \
        --x-install-root="$spatial_dir/vcpkg_installed" --overlay-triplets="$custom_triplets_dir"
}

build_for_abi() {
    local abi=$1
    local triplet=$2
    local platform_name="android_${abi}"
    local spatial_dir="${PROJECT_ROOT}/build/spatial/duckdb-spatial"
    local duckpgq_dir="${PROJECT_ROOT}/build/duckpgq/duckpgq-extension"
    local build_path="$spatial_dir/build/${platform_name}"
    local vss_config="${PROJECT_ROOT}/build/vss/vss_extension_config.cmake"
    local duckpgq_config="${PROJECT_ROOT}/build/duckpgq/duckpgq_extension_config.cmake"
    
    log_step "Building DuckDB for $abi..."
    
    install_vcpkg_deps "$triplet"
    
    local host_triplet
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then host_triplet="arm64-osx"; else host_triplet="x64-osx"; fi
    else
        host_triplet="x64-linux"
    fi
    
    rm -rf "$build_path"
    mkdir -p "$build_path"
    
    local num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    local custom_triplets_dir="$spatial_dir/custom-triplets"
    
    cmake -G "Ninja" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
        -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
        -DVCPKG_TARGET_TRIPLET="$triplet" \
        -DVCPKG_HOST_TRIPLET="$host_triplet" \
        -DVCPKG_INSTALLED_DIR="$spatial_dir/vcpkg_installed" \
        -DVCPKG_OVERLAY_PORTS="$spatial_dir/vcpkg_ports" \
        -DVCPKG_OVERLAY_TRIPLETS="$custom_triplets_dir" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
        -DEXTENSION_STATIC_BUILD=ON \
        -DDUCKDB_EXTENSION_CONFIGS="$spatial_dir/extension_config.cmake;$vss_config;$duckpgq_config" \
        -DSPATIAL_USE_NETWORK=ON \
        -DBUILD_SHELL=OFF \
        -DBUILD_UNITTESTS=OFF \
        -DENABLE_EXTENSION_AUTOLOADING=ON \
        -DENABLE_EXTENSION_AUTOINSTALL=OFF \
        -DDUCKDB_EXTRA_LINK_FLAGS="-llog -Wl,-z,max-page-size=16384" \
        -DDUCKDB_EXPLICIT_PLATFORM="$platform_name" \
        -DLOCAL_EXTENSION_REPO="" \
        -DOVERRIDE_GIT_DESCRIBE="" \
        -DBUILD_EXTENSIONS="$DUCKDB_EXTENSIONS" \
        -S "$duckpgq_dir/duckdb" \
        -B "$build_path"
    
    cmake --build "$build_path" --config Release -- -j$num_cores
    
    local output_abi_dir="${OUTPUT_DIR}/jniLibs/${abi}"
    mkdir -p "$output_abi_dir"
    
    if [ -f "$build_path/src/libduckdb.so" ]; then
        cp "$build_path/src/libduckdb.so" "$output_abi_dir/"
        log_info "Copied libduckdb.so to $output_abi_dir"
        
        # Also copy libc++_shared.so
        local libcxx_path=""
        if [ "$abi" == "arm64-v8a" ]; then
            libcxx_path="${ANDROID_NDK}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
        elif [ "$abi" == "x86_64" ]; then
            libcxx_path="${ANDROID_NDK}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so"
        fi
        
        if [ -f "$libcxx_path" ]; then
            cp "$libcxx_path" "$output_abi_dir/"
            log_info "Copied libc++_shared.so to $output_abi_dir"
        else
            log_warn "libc++_shared.so not found at $libcxx_path"
        fi
    else
        log_error "libduckdb.so not found!"
        exit 1
    fi
}

main() {
    log_info "=== DuckDB Android Build Script (Monolithic) ==="
    check_tools
    check_ndk
    check_vcpkg
    
    get_spatial_source
    get_vss_source
    get_duckpgq_source
    create_vss_extension_config
    create_duckpgq_extension_config
    
    build_for_abi "arm64-v8a" "arm64-android"
    build_for_abi "x86_64" "x64-android"
    
    log_info "=== Build complete! ==="
    log_info "Output: ${OUTPUT_DIR}/jniLibs/"
}

main
