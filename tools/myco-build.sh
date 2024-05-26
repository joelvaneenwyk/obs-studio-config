
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
buildspec="${{ github.workspace }}/third-party/obs-studio/buildspec.json"

# Prebuilt Dependencies Version
IFS=$'\n' buildspecdata=($(node tools/buildspec.js "${buildspec}" "prebuilt" "windows-x64"))
echo "obs_deps_version=${buildspecdata[0]}" >> "$GITHUB_ENV"
echo "obs_deps_hash=${buildspecdata[1]}" >> "$GITHUB_ENV"
echo "obs_deps_url=${buildspecdata[2]}" >> "$GITHUB_ENV"

# Qt Version
IFS=$'\n' buildspecdata=($(node tools/buildspec.js "${buildspec}" "qt${{ matrix.qt }}" "windows-x64"))
echo "qt_version=${buildspecdata[0]}" >> "$GITHUB_ENV"
echo "qt_hash=${buildspecdata[1]}" >> "$GITHUB_ENV"
echo "qt_url=${buildspecdata[2]}" >> "$GITHUB_ENV"

# libOBS Version
echo "obs_version=$(cd "${{ github.workspace }}/third-party/obs-studio" && git describe --tags --long)" >> "$GITHUB_ENV"

# - name: "Dependency: Qt (Cache)"
# id: qt-cache
# uses: actions/cache@v3
# with:
# 	path: "${{ github.workspace }}/build/qt"
# 	key: "qt${{ env.qt_hash }}-${{ env.CACHE_VERSION }}"

# - name: "Dependency: Qt"
# id: qt
# if: ${{ steps.qt-cache.outputs.cache-hit != 'true' }}
# shell: bash
# run: |
curl --retry 5 --retry-delay 30 -jLo /tmp/qt.zip "${{ env.qt_url }}"
if [[ ! -f "${{ github.workspace }}/build/qt" ]]; then mkdir -p "${{ github.workspace }}/build/qt"; fi
7z x -y -o"${{ github.workspace }}/build/qt" -- "/tmp/qt.zip"

# - name: "Dependency: Prebuilt OBS Studio Dependencies (Cache)"
# id: obsdeps-cache
# uses: actions/cache@v3
# with:
# 	path: "${{ github.workspace }}/build/obsdeps"
# 	key: "obsdeps${{ env.obs_deps_hash }}-${{ env.CACHE_VERSION }}"

# - name: "Dependency: Prebuilt OBS Studio Dependencies"
# id: obsdeps
# if: ${{ steps.obsdeps-cache.outputs.cache-hit != 'true' }}
# shell: bash
# run: |
curl --retry 5 --retry-delay 30 -jLo /tmp/obsdeps.zip "${{ env.obs_deps_url }}"
if [[ ! -f "${{ github.workspace }}/build/obsdeps" ]]; then mkdir -p "${{ github.workspace }}/build/obsdeps"; fi
7z x -y -o"${{ github.workspace }}/build/obsdeps" -- "/tmp/obsdeps.zip"

# - name: "Dependency: OBS Libraries (Cache)"
# id: obs-cache
# uses: actions/cache@v3
# with:
# 	path: "${{ github.workspace }}/build/obs"
# 	key: "obs${{ env.obs_version }}-${{ matrix.runner }}_${{ matrix.compiler }}-obsdeps${{ env.obs_deps_hash }}-qt${{ env.qt_hash }}-${{ env.CACHE_VERSION }}"

# - name: "Dependency: OBS Libraries"
# id: obs
# if: ${{ steps.obs-cache.outputs.cache-hit != 'true' }}
# env:
# obs-studio does not support ClangCL
CMAKE_GENERATOR_TOOLSET=""
# shell: bash
# run: |
# Apply patches to obs-studio
pushd "${{ github.workspace }}/third-party/obs-studio" > /dev/null
for f in ../../patches/obs-studio/*.patch; do
echo "Applying patch '${f}''..."
[ -e "$f" ] || continue
git apply "$f"
done
popd > /dev/null

# Build obs-studio
cmake \
-S "${{ github.workspace }}/third-party/obs-studio" \
-B "${{ github.workspace }}/build/obs" \
-DCMAKE_SYSTEM_VERSION="${{ env.CMAKE_SYSTEM_VERSION }}" \
-DCMAKE_INSTALL_PREFIX="${{ github.workspace }}/build/obs/install" \
-DCMAKE_PREFIX_PATH="${{ github.workspace }}/build/obsdeps;${{ github.workspace }}/build/qt" \
-DENABLE_PLUGINS=OFF \
-DENABLE_UI=OFF \
-DENABLE_SCRIPTING=OFF
cmake \
--build "${{ github.workspace }}/build/obs" \
--config RelWithDebInfo \
--target obs-frontend-api
cmake \
--install "${{ github.workspace }}/build/obs" \
--config RelWithDebInfo \
--component obs_libraries

# - name: "Configure"
# continue-on-error: true
# shell: bash
# run: |
cmake \
-S "${{ github.workspace }}" \
-B "${{ github.workspace }}/build/ci" \
-DCMAKE_SYSTEM_VERSION="${{ env.CMAKE_SYSTEM_VERSION }}" \
-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
-Dlibobs_DIR="${{ github.workspace }}/build/obs/install" \
-DQt${{ matrix.qt }}_DIR="${{ github.workspace }}/build/qt" \
-DFFmpeg_DIR="${{ github.workspace }}/build/obsdeps" \
-DCURL_DIR="${{ github.workspace }}/build/obsdeps"

# - name: "Build: Debug"
# continue-on-error: true
# shell: bash
# env:
CMAKE_BUILD_TYPE= "Debug"
# run: |
cmake --build "build/ci" --config ${{ env.CMAKE_BUILD_TYPE }} --target StreamFX

# - name: "Build: Release"
# shell: bash
# env:
CMAKE_BUILD_TYPE="RelWithDebInfo"
# run: |
cmake --build "build/ci" --config ${{ env.CMAKE_BUILD_TYPE }} --target StreamFX
