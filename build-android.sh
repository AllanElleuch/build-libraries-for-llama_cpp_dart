#!/usr/bin/env bash
#
# Build script for Android
# This script builds llama.cpp native libraries for Android
#

set -e

# Options
ANDROID_MIN_SDK_VERSION=23
ANDROID_TARGET_SDK_VERSION=34

# Build configuration
BUILD_SHARED_LIBS=ON
LLAMA_BUILD_EXAMPLES=OFF
LLAMA_BUILD_TOOLS=OFF
LLAMA_BUILD_TESTS=OFF
LLAMA_BUILD_SERVER=OFF
LLAMA_BUILD_COMMON=ON
LLAMA_CURL=OFF
GGML_OPENMP=OFF
GGML_LLAMAFILE=OFF

# Check if ANDROID_NDK is set
if [ -z "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK environment variable is not set"
    echo "Please set it to your Android NDK path, e.g.:"
    echo "  export ANDROID_NDK=~/Android/Sdk/ndk/26.1.10909125"
    exit 1
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK path does not exist: $ANDROID_NDK"
    exit 1
fi

echo "Using Android NDK: $ANDROID_NDK"

# Android ABIs to build
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")

# Common CMake arguments
COMMON_CMAKE_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
    -DANDROID_PLATFORM=android-${ANDROID_MIN_SDK_VERSION}
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DLLAMA_BUILD_EXAMPLES=${LLAMA_BUILD_EXAMPLES}
    -DLLAMA_BUILD_TOOLS=${LLAMA_BUILD_TOOLS}
    -DLLAMA_BUILD_TESTS=${LLAMA_BUILD_TESTS}
    -DLLAMA_BUILD_SERVER=${LLAMA_BUILD_SERVER}
    -DLLAMA_BUILD_COMMON=${LLAMA_BUILD_COMMON}
    -DLLAMA_CURL=${LLAMA_CURL}
    -DGGML_OPENMP=${GGML_OPENMP}
    -DGGML_LLAMAFILE=${GGML_LLAMAFILE}
    -DCMAKE_BUILD_TYPE=Release
)

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf build-android-*
rm -rf android-libs

# Build for each ABI
for ABI in "${ABIS[@]}"; do
    echo ""
    echo "=========================================="
    echo "Building for ABI: $ABI"
    echo "=========================================="

    BUILD_DIR="build-android-${ABI}"

    # Set architecture-specific flags
    case $ABI in
        arm64-v8a)
            ARCH_FLAGS="-march=armv8.2-a+dotprod"
            ;;
        armeabi-v7a)
            ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=neon"
            ;;
        x86_64)
            ARCH_FLAGS="-march=x86-64"
            ;;
        x86)
            ARCH_FLAGS="-march=i686"
            ;;
    esac

    # Configure
    echo "Configuring..."
    cmake -B ${BUILD_DIR} \
        "${COMMON_CMAKE_ARGS[@]}" \
        -DANDROID_ABI=${ABI} \
        -DCMAKE_C_FLAGS="${ARCH_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${ARCH_FLAGS}"

    # Build
    echo "Building..."
    cmake --build ${BUILD_DIR} --config Release -j$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

    # Install to ABI-specific directory
    echo "Installing..."
    INSTALL_DIR="android-libs/${ABI}"
    cmake --install ${BUILD_DIR} --prefix ${INSTALL_DIR} --config Release

    echo "✓ Completed build for $ABI"
done

echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo "All ABIs built successfully!"
echo "Libraries are in: android-libs/"
echo ""
echo "Directory structure:"
tree -L 3 android-libs/ 2>/dev/null || find android-libs -type f

echo ""
echo "=========================================="
echo "Creating AAR package (optional)"
echo "=========================================="

# Create AAR structure
AAR_DIR="build-aar"
rm -rf ${AAR_DIR}
mkdir -p ${AAR_DIR}/jni

# Copy libraries for each ABI
for ABI in "${ABIS[@]}"; do
    mkdir -p ${AAR_DIR}/jni/${ABI}
    if [ -d "android-libs/${ABI}/lib" ]; then
        cp android-libs/${ABI}/lib/*.so ${AAR_DIR}/jni/${ABI}/ 2>/dev/null || true
    fi
done

# Create AndroidManifest.xml
cat > ${AAR_DIR}/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.ggml.llama">
    <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="34"/>
</manifest>
EOF

# Create classes.jar (empty)
mkdir -p ${AAR_DIR}/classes
jar cf ${AAR_DIR}/classes.jar -C ${AAR_DIR}/classes .

# Create R.txt (empty)
touch ${AAR_DIR}/R.txt

# Package AAR
cd ${AAR_DIR}
zip -r ../llama-android.aar AndroidManifest.xml classes.jar jni/ R.txt
cd ..

if [ -f "llama-android.aar" ]; then
    echo "✓ AAR package created: llama-android.aar"
    echo ""
    echo "To use this AAR in your Android project:"
    echo "1. Copy llama-android.aar to your project's libs/ directory"
    echo "2. Add to your app/build.gradle:"
    echo "   implementation files('libs/llama-android.aar')"
else
    echo "⚠ AAR package creation skipped (requires jar/zip commands)"
fi

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
