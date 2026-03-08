#!/bin/bash

# 1. [Root 권한] 호스트 볼륨 권한 자동 수정 및 초기화
echo "[INFO] Fixing permissions and FEX environment..."
mkdir -p "/home/steam/core-keeper-data"

_fix_owner() {
    local dir="$1"
    [ -e "$dir" ] || return
    if [ "$(stat -c '%u' "$dir")" != "1000" ]; then
        echo "[INFO] Fixing ownership of $dir ..."
        chown -R 1000:1000 "$dir"
    fi
}
_fix_owner "/home/steam/core-keeper-data"

if [ -d "/home/steam/core-keeper-dedicated" ] && [ "$(stat -c '%u' "/home/steam/core-keeper-dedicated")" != "1000" ]; then
    echo "[INFO] Fixing ownership of /home/steam/core-keeper-dedicated (top-level only)..."
    chown 1000:1000 "/home/steam/core-keeper-dedicated"
fi

# 임시 폴더 및 캐시 청소 (복불복 실행 방지)
rm -rf /tmp/Pugstorm
mkdir -p "/tmp/Pugstorm/Core Keeper"
chmod -R 777 /tmp/Pugstorm
chown -R 1000:1000 /tmp/Pugstorm
rm -rf /home/steam/.fex-emu/AppConfig/

FEX_ROOT="/home/steam/.fex-emu/RootFS"
if [ -d "$FEX_ROOT/Ubuntu_22.04" ] && [ ! -d "$FEX_ROOT/Ubuntu_22_04" ]; then
    ln -s "$FEX_ROOT/Ubuntu_22.04" "$FEX_ROOT/Ubuntu_22_04"
fi
rm -f /tmp/.X1-lock

# 2. [steam 유저 전환]
# 여기서부터는 'steam' 유저 권한으로 실행됩니다.
exec gosu steam bash << 'EOF'

# 경로 및 환경 변수 설정
export EXTERNAL_DIR="/home/steam/core-keeper-data"
export GAME_DIR="/home/steam/core-keeper-dedicated"
export STEAM_SDK_DIR="/home/steam/.steam/sdk64"
export MODSDIR="${GAME_DIR}/CoreKeeperServer_Data/StreamingAssets/Mods"

# FEX 안정성 옵션 (모드 사용 시 필수)
export FEX_TSO=0
export FEX_SMC=1
export FEX_LLVM=1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export DISPLAY=:1
export LD_LIBRARY_PATH="$GAME_DIR/linux64:$LD_LIBRARY_PATH"

# 3. 통합 심볼릭 링크 및 게임 업데이트 (기존 로직 동일)
INTERNAL_PARENT="/home/steam/.config/unity3d/Pugstorm/Core Keeper"
INTERNAL_DIR="$INTERNAL_PARENT/DedicatedServer"
mkdir -p "$INTERNAL_PARENT"
[ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ] && rm -rf "$INTERNAL_DIR"
[ ! -L "$INTERNAL_DIR" ] && ln -s "$EXTERNAL_DIR" "$INTERNAL_DIR"

if [ ! -f "$GAME_DIR/CoreKeeperServer" ]; then
    echo "[INFO] Downloading game files..."
    /usr/local/bin/DepotDownloader -app 1963720 -dir "$GAME_DIR" -os linux
fi
chmod +x "$GAME_DIR/CoreKeeperServer"

# 4. Xvfb 실행
Xvfb :1 -screen 0 1024x768x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
for i in $(seq 1 30); do
    [ -S /tmp/.X11-unix/X1 ] && break
    sleep 1
done

# 5. 모드 관리 함수 (기존 로직 동일)
MODIO_CORE_KEEPER_ENDPOINT="${MODIO_API_URL}/games/@corekeeper/mods"
download_and_install_mod() {
    local mod_string_id="$1"
    local version="$2"
    local modio_mod_endpoint="${MODIO_CORE_KEEPER_ENDPOINT}/@${mod_string_id}"
    local mod_info=$(curl -s "${modio_mod_endpoint}?api_key=${MODIO_API_KEY}")
    local mod_name=$(echo "$mod_info" | jq -r ".name")
    local download_url=$(echo "$mod_info" | jq -r ".modfile.download.binary_url")
    local actual_version=$(echo "$mod_info" | jq -r ".modfile.version")
    
    local temp_dir=$(mktemp -d)
    local temp_zip="${temp_dir}/mod.zip"
    if curl -s -L "${download_url}?api_key=${MODIO_API_KEY}" -o "${temp_zip}"; then
        mkdir -p "${MODSDIR}/${mod_string_id}"
        unzip -q "${temp_zip}" -d "${MODSDIR}/${mod_string_id}"
        echo "[INFO] Installed ${mod_name} (${mod_string_id}) ${actual_version}"
    fi
    rm -rf "${temp_dir}"
}

manage_mods() {
    rm -rf "${MODSDIR}" && mkdir -p "${MODSDIR}"
    [ "${MODS_ENABLED,,}" != "true" ] && return 0
    IFS=',' read -ra mod_list <<< "$MODS"
    for mod_spec in "${mod_list[@]}"; do
        mod_spec=$(echo "$mod_spec" | xargs)
        local m_id="${mod_spec%%:*}"
        local m_ver=""
        [[ "$mod_spec" == *":"* ]] && m_ver="${mod_spec#*:}"
        download_and_install_mod "$m_id" "$m_ver"
    done
}

manage_mods

# 6. [4코어 최적화] 서버 실행 및 모든 스레드 코어 확장
cd "$GAME_DIR"
SERVER_LOG="/tmp/server_boot.log"
rm -f "$SERVER_LOG"

echo "[INFO] Starting Server on Core 0 (Strict Safe Mode)..."

# 초기 실행은 0번 코어에 고정
taskset -c 0 /usr/bin/FEXInterpreter ./CoreKeeperServer \
    -batchmode -force-opengl -logfile - \
    -worldname "$WORLD_NAME" -worldindex "${WORLD_INDEX:-0}" \
    -maxplayers "${MAX_PLAYERS:-5}" -port "${SERVER_PORT:-27015}" \
    -password "$PASSWORD" -job-worker-count 4 \
    -savedirectory "$EXTERNAL_DIR" \
    -allowonlyplatform "${ALLOW_ONLY_PLATFORM:-0}" \
    $MOD_ARGS > >(tee "$SERVER_LOG") 2>&1 &

SERVER_PID=$!

(
    echo "[WATCHER] Waiting for 'Started session with info' to unlock all threads..."
    while sleep 3; do
        if grep -q "Started session with info" "$SERVER_LOG"; then
            echo "----------------------------------------------------------"
            echo "[WATCHER] Session started! Unlocking ALL THREADS for 4 CORES."
            taskset -a -p -c 0,1,2,3 $SERVER_PID
            
            echo "[WATCHER] All CPU threads are now free to use Cores 0-3."
            echo "----------------------------------------------------------"
            break
        fi
        
        if ! kill -0 $SERVER_PID 2>/dev/null; then break; fi
    done
) &

wait $SERVER_PID
EOF