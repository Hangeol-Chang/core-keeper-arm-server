FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# 필수 패키지 및 FEX-Emu 설치
RUN apt update && apt install -y \
    curl python3 sudo expect-dev software-properties-common \
    xvfb libxi6 tini tzdata gosu jo jq gettext-base unzip wget \
    libdbus-1-3 libxcursor1 libxinerama1 libxss1 libgl1-mesa-dri mesa-utils \
    squashfs-tools \
    && add-apt-repository -y ppa:fex-emu/fex && apt update && apt install -y fex-emu-armv8.2

# 시스템 설정 및 유저 생성
RUN ln -sf /bin/true /usr/bin/systemctl && mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
RUN useradd -m -u 1000 steam
WORKDIR /home/steam

# FEX RootFS 설치 (FEXRootFSFetcher는 Docker 빌드 환경에서 zenity/TTY 없이 동작 불가)
# curl로 Ubuntu 22.04 SquashFS 직접 다운로드 후 unsquashfs로 추출
USER steam
ENV HOME=/home/steam
RUN mkdir -p /home/steam/.fex-emu/RootFS && \
    curl -fSL "https://rootfs.fex-emu.gg/Ubuntu_22_04/2025-01-08/Ubuntu_22_04.sqsh" \
         -o /home/steam/.fex-emu/RootFS/Ubuntu_22_04.sqsh && \
    unsquashfs -d /home/steam/.fex-emu/RootFS/Ubuntu_22_04 \
               /home/steam/.fex-emu/RootFS/Ubuntu_22_04.sqsh && \
    rm /home/steam/.fex-emu/RootFS/Ubuntu_22_04.sqsh

# FEX 설정 강제 주입 (추출된 디렉토리 경로로 고정)
RUN echo '{"Config":{"RootFS":"/home/steam/.fex-emu/RootFS/Ubuntu_22_04"}}' \
    > /home/steam/.fex-emu/Config.json

# DepotDownloader 설치 (ARM64 네이티브)
USER root
RUN wget https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-linux-arm64.zip \
    && unzip DepotDownloader-linux-arm64.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/DepotDownloader \
    && rm DepotDownloader-linux-arm64.zip

# 작업 폴더 준비 및 권한 부여
RUN mkdir -p /home/steam/core-keeper-dedicated /home/steam/core-keeper-data /home/steam/scripts \
    && chown -R steam:steam /home/steam

# 스크립트 복사 및 실행 권한
COPY ./scripts /home/steam/scripts
RUN chmod +x /home/steam/scripts/*.sh && chown -R steam:steam /home/steam/scripts

# 최종 실행은 root로 시작 (init-server.sh에서 권한 해결 후 유저 전환)
USER root
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/home/steam/scripts/init-server.sh"]
