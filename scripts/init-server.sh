#!/bin/bash

# 1. [Root 권한] 호스트 볼륨 권한 자동 수정 및 FEX 경로 복구
echo "[INFO] Fixing permissions and FEX environment..."
mkdir -p "/home/steam/core-keeper-data"
chown -R 1000:1000 "/home/steam/core-keeper-data"
chown -R 1000:1000 "/home/steam/core-keeper-dedicated"

# FEX RootFS 경로 유효성 강제 확보 (점 vs 언더바 해결)
FEX_ROOT="/home/steam/.fex-emu/RootFS"
if [ -d "$FEX_ROOT/Ubuntu_22.04" ] && [ ! -d "$FEX_ROOT/Ubuntu_22_04" ]; then
    ln -s "$FEX_ROOT/Ubuntu_22.04" "$FEX_ROOT/Ubuntu_22_04"
fi
chown -R 1000:1000 "/home/steam/.fex-emu"
rm -f /tmp/.X1-lock

# 2. [steam 유저 전환] 모든 환경 변수를 유지하며 진입
exec gosu steam bash << 'EOF'

# 경로 변수 설정
export EXTERNAL_DIR="/home/steam/core-keeper-data"
export GAME_DIR="/home/steam/core-keeper-dedicated"
export STEAM_SDK_DIR="/home/steam/.steam/sdk64"

# 3. 통합 심볼릭 링크 (DedicatedServer 폴더 전체 공유)
INTERNAL_PARENT="/home/steam/.config/unity3d/Pugstorm/Core Keeper"
INTERNAL_DIR="$INTERNAL_PARENT/DedicatedServer"
mkdir -p "$INTERNAL_PARENT"
[ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ] && rm -rf "$INTERNAL_DIR"
[ ! -L "$INTERNAL_DIR" ] && ln -s "$EXTERNAL_DIR" "$INTERNAL_DIR"

# 4. 게임 업데이트 및 실행 권한 확인
if [ ! -f "$GAME_DIR/CoreKeeperServer" ]; then
    echo "[INFO] Downloading game files..."
    # Core Keeper 전용 서버는 익명 스팀 로그인으로 다운로드 가능
    /usr/local/bin/DepotDownloader -app 1963720 -dir "$GAME_DIR" -os linux -username anonymous
fi
chmod +x "$GAME_DIR/CoreKeeperServer"

# 5. Steam SDK 링크 보강
mkdir -p "$STEAM_SDK_DIR"
if [ -f "$GAME_DIR/linux64/steamclient.so" ]; then
    ln -sf "$GAME_DIR/linux64/steamclient.so" "$STEAM_SDK_DIR/steamclient.so"
fi

# 6. ServerConfig.json 업데이트 (jq)
if [ ! -f "$EXTERNAL_DIR/ServerConfig.json" ]; then
    echo '{"gameId":"","world":0,"worldName":"Core Keeper","worldSeed":0,"maxNumberPlayers":100,"maxNumberPacketsSentPerFrame":1,"networkSendRate":30,"worldMode":0,"seasonOverride":-1}' > "$EXTERNAL_DIR/ServerConfig.json"
fi
tmp_json=$(mktemp)
jq --arg gameId "$GAME_ID" --arg worldName "$WORLD_NAME" --argjson world "${WORLD_INDEX:-0}" --argjson maxPlayers "${MAX_PLAYERS:-5}" --argjson season "${SEASON:--1}" '.gameId = $gameId | .worldName = $worldName | .world = $world | .maxNumberPlayers = $maxPlayers | .seasonOverride = $season' "$EXTERNAL_DIR/ServerConfig.json" > "$tmp_json" && mv "$tmp_json" "$EXTERNAL_DIR/ServerConfig.json"

# 7. 지능형 코어(Worker) 할당
if [ "$(ls -A "$EXTERNAL_DIR/worlds" 2>/dev/null | grep '\.pug$')" ]; then
    echo "[INFO] Existing world detected. Performance mode (Worker: 2)"
    WORKER_COUNT=2
else
    echo "[INFO] No world found. Safety mode (Worker: 1)"
    WORKER_COUNT=1
fi

# 8. FEX 및 가상 디스플레이 환경 변수
export FEX_TSO=1
export FEX_SMC=1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export DISPLAY=:1
export LD_LIBRARY_PATH="$GAME_DIR/linux64:$LD_LIBRARY_PATH"

Xvfb :1 -screen 0 1024x768x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
# Xvfb 소켓이 생성될 때까지 대기 (최대 30초) - 고정 sleep 대신 실제 준비 여부 확인
for i in $(seq 1 30); do
    if [ -S /tmp/.X11-unix/X1 ]; then
        echo "[INFO] Xvfb is ready."
        break
    fi
    sleep 1
done
if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "[ERROR] Xvfb failed to start. Exiting."
    exit 1
fi

# 9. 서버 실행 (PID 1 유지 및 stdout 로그)
cd "$GAME_DIR"
echo "[INFO] Starting Core Keeper Server..."
# 모드 관련 인자 조립 (MODS_ENABLED=true 일 때만 활성화)
MOD_ARGS=""
if [ "${MODS_ENABLED:-false}" = "true" ]; then
    MOD_ARGS="-modsEnabled"
    [ -n "${MODIO_API_KEY}" ]  && MOD_ARGS="$MOD_ARGS -modioApiKey $MODIO_API_KEY"
    [ -n "${MODIO_API_URL}" ]  && MOD_ARGS="$MOD_ARGS -modioApiUrl $MODIO_API_URL"
    [ -n "${MODS}" ]           && MOD_ARGS="$MOD_ARGS -mods $MODS"
fi

exec /usr/bin/FEXInterpreter ./CoreKeeperServer \
    -batchmode -force-opengl -logfile - \
    -worldname "$WORLD_NAME" -worldindex "${WORLD_INDEX:-0}" \
    -maxplayers "${MAX_PLAYERS:-5}" -port "${SERVER_PORT:-27015}" \
    -password "$PASSWORD" -job-worker-count $WORKER_COUNT \
    -savedirectory "$EXTERNAL_DIR" \
    -allowonlyplatform "${ALLOW_ONLY_PLATFORM:-0}" \
    $MOD_ARGS

EOF
