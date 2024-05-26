#!/usr/bin/env bash

## Find and replace
##      \$\{\{ env\.([a-zA-Z\d_]+) \}\}
##      $${$1}

function main() {
    set -eax -o pipefail

    obs_studio_config="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" &>/dev/null && cd ../ && pwd)"
    obs_streamfx="$(cd "$(realpath "${obs_studio_config}/external/obs-StreamFX")" &>/dev/null && pwd)"

    obs_tmp="${obs_streamfx}/tmp"
    mkdir -p "${obs_tmp}"

    echo "obs_studio_config: ${obs_studio_config}"
    echo "obs_streamfx: ${obs_streamfx}"

    cd "${obs_streamfx}" || true
    git submodule update --init --recursive

    # - name: "Clone"
    # uses: actions/checkout@v4
    # with:
    # 	submodules: recursive
    # 	fetch-depth: 0

    # - name: "Gather Information"
    # id: info
    # shell: bash
    # run: |
    # Define buildspec file
    buildspec="${obs_streamfx}/third-party/obs-studio/buildspec.json"

    GITHUB_ENV="${obs_streamfx}/.env"
    rm -f "$GITHUB_ENV"

    # Prebuilt Dependencies Version
    IFS=$'\n' buildspecdata=($(node ${obs_streamfx}/tools/buildspec.js "${buildspec}" "prebuilt" "windows-x64"))
    echo "obs_deps_version=${buildspecdata[0]}" >>"$GITHUB_ENV"
    echo "obs_deps_hash=${buildspecdata[1]}" >>"$GITHUB_ENV"
    echo "obs_deps_url=${buildspecdata[2]}" >>"$GITHUB_ENV"

    # Qt Version
    QT_VERSION=6
    IFS=$'\n' buildspecdata=($(node "${obs_streamfx}/tools/buildspec.js" "${buildspec}" "qt${QT_VERSION}" "windows-x64"))
    echo "qt_version=${buildspecdata[0]}" >>"$GITHUB_ENV"
    echo "qt_hash=${buildspecdata[1]}" >>"$GITHUB_ENV"
    echo "qt_url=${buildspecdata[2]}" >>"$GITHUB_ENV"

    # libOBS Version
    echo "obs_version=$(cd "${obs_streamfx}/third-party/obs-studio" && git describe --tags --long)" >>"$GITHUB_ENV"

    eval "$(cat "$GITHUB_ENV")"

    # - name: "Dependency: Qt (Cache)"
    # id: qt-cache
    # uses: actions/cache@v3
    # with:
    # 	path: "${obs_streamfx}/build/qt"
    # 	key: "qt${qt_hash}-${CACHE_VERSION}"

    # - name: "Dependency: Qt"
    # id: qt
    # if: ${{ steps.qt-cache.outputs.cache-hit != 'true' }}
    # shell: bash
    # run: |
    curl --retry 5 --retry-delay 30 -jLo ${obs_tmp}/qt.zip "${qt_url}"
    if [[ ! -f "${obs_streamfx}/build/qt" ]]; then mkdir -p "${obs_streamfx}/build/qt"; fi
    7z x -y -o"${obs_streamfx}/build/qt" -- "${obs_tmp}/qt.zip"

    # - name: "Dependency: Prebuilt OBS Studio Dependencies (Cache)"
    # id: obsdeps-cache
    # uses: actions/cache@v3
    # with:
    # 	path: "${obs_streamfx}/build/obsdeps"
    # 	key: "obsdeps${obs_deps_hash}-${CACHE_VERSION}"

    # - name: "Dependency: Prebuilt OBS Studio Dependencies"
    # id: obsdeps
    # if: ${{ steps.obsdeps-cache.outputs.cache-hit != 'true' }}
    # shell: bash
    # run: |
    curl --retry 5 --retry-delay 30 -jLo "${obs_tmp}/obsdeps.zip" "${obs_deps_url}"
    if [[ ! -f "${obs_streamfx}/build/obsdeps" ]]; then mkdir -p "${obs_streamfx}/build/obsdeps"; fi
    7z x -y -o"${obs_streamfx}/build/obsdeps" -- "${obs_tmp}/obsdeps.zip"

    # - name: "Dependency: OBS Libraries (Cache)"
    # id: obs-cache
    # uses: actions/cache@v3
    # with:
    # 	path: "${obs_streamfx}/build/obs"
    # 	key: "obs${obs_version}-${{ matrix.runner }}_${{ matrix.compiler }}-obsdeps${obs_deps_hash}-qt${qt_hash}-${CACHE_VERSION}"

    # - name: "Dependency: OBS Libraries"
    # id: obs
    # if: ${{ steps.obs-cache.outputs.cache-hit != 'true' }}
    # env:
    # obs-studio does not support ClangCL
    CMAKE_GENERATOR_TOOLSET=""
    # shell: bash
    # run: |
    # Apply patches to obs-studio
    pushd "${obs_streamfx}/third-party/obs-studio" >/dev/null
    for f in ${obs_streamfx}/patches/obs-studio/*.patch; do
        echo "Applying patch '${f}''..."
        [ -e "$f" ] || continue
        git apply "$f"
    done
    popd >/dev/null

    # Build obs-studio
    cmake \
        -S "${obs_streamfx}/third-party/obs-studio" \
        -B "${obs_streamfx}/build/obs" \
        -DCMAKE_SYSTEM_VERSION="${CMAKE_SYSTEM_VERSION}" \
        -DCMAKE_INSTALL_PREFIX="${obs_streamfx}/build/obs/install" \
        -DCMAKE_PREFIX_PATH="${obs_streamfx}/build/obsdeps;${obs_streamfx}/build/qt" \
        -DENABLE_PLUGINS=OFF \
        -DENABLE_UI=OFF \
        -DENABLE_SCRIPTING=OFF
    cmake \
        --build "${obs_streamfx}/build/obs" \
        --config RelWithDebInfo \
        --target obs-frontend-api
    cmake \
        --install "${obs_streamfx}/build/obs" \
        --config RelWithDebInfo \
        --component obs_libraries

    # - name: "Configure"
    # continue-on-error: true
    # shell: bash
    # run: |
    cmake \
        -S "${obs_streamfx}" \
        -B "${obs_streamfx}/build/ci" \
        -DCMAKE_SYSTEM_VERSION="${CMAKE_SYSTEM_VERSION}" \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -Dlibobs_DIR="${obs_streamfx}/build/obs/install" \
        -DQt${QT_VERSION}_DIR="${obs_streamfx}/build/qt" \
        -DFFmpeg_DIR="${obs_streamfx}/build/obsdeps" \
        -DCURL_DIR="${obs_streamfx}/build/obsdeps"

    # - name: "Build: Debug"
    # continue-on-error: true
    # shell: bash
    # env:
    CMAKE_BUILD_TYPE= "Debug"
    # run: |
    cmake --build "build/ci" --config "${CMAKE_BUILD_TYPE}" --target StreamFX

    # - name: "Build: Release"
    # shell: bash
    # env:
    CMAKE_BUILD_TYPE="RelWithDebInfo"
    # run: |
    cmake --build "build/ci" --config "${CMAKE_BUILD_TYPE}" --target StreamFX
}

main "$@"
