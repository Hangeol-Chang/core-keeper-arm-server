# Core Keeper Dedicated Server (ARM64)

> [English](../README.md) | **한국어**

Oracle A1 등 **ARM64** 환경에서 [FEX-Emu](https://fex-emu.com/)를 통해 Core Keeper 전용 서버를 실행하는 Docker 이미지입니다.

> **지원 환경:** ARM64 호스트 (Oracle Cloud A1, Ampere 등)

---

## 사전 요구사항

- Docker & Docker Compose 설치
- ARM64 호스트 (Oracle A1 Flex 등)
- mod.io API 키 (모드 사용 시)

---

## 1. 실행법

### 1-1. 파일 준비

```bash
git clone https://github.com/Hangeol-Chang/core-keeper-arm-server.git
cd core-keeper-arm-server
```

### 1-2. 환경 변수 설정

`core.env.example`을 복사하여 `core.env` 파일을 만들고 값을 채웁니다.

```bash
cp core.env.example core.env
```

`core.env` 파일을 편집합니다:

```dotenv
WORLD_NAME="내 서버 이름"       # 서버/월드 이름
MAX_PLAYERS=5                   # 최대 플레이어 수
WORLD_INDEX=0                   # 월드 슬롯 번호 (0~2)
SEASON=0                        # 시즌 설정

GAME_ID=my-unique-server-id     # 서버 고유 ID (Steam 로비 식별자)
SERVER_PORT=27015               # 서버 포트 (UDP)
PASSWORD=your_password          # 서버 접속 비밀번호 (없으면 빈칸)
ALLOW_ONLY_PLATFORM=1           # 1: Steam 전용, 0: 크로스플랫폼
```

### 1-3. 데이터 폴더 생성

월드 세이브 등 영구 데이터를 저장할 폴더를 만듭니다.

```bash
mkdir -p data
```

### 1-4. 이미지 Pull 및 서버 실행

```bash
# 최신 이미지를 받아서 백그라운드로 실행
docker compose up -d
```

### 1-5. 로그 확인

```bash
docker logs -f ck-server
```

아래 메시지가 뜨면 서버가 정상적으로 열린 것입니다:

```
Started session with info ...
```

### 1-6. 서버 중지 / 재시작

```bash
docker compose down       # 중지
docker compose restart    # 재시작
```

### 포트 방화벽 설정

Oracle Cloud를 사용하는 경우, 인스턴스의 **Security List** 및 **OS 방화벽** 양쪽에서 포트를 열어야 합니다.

```bash
# UFW 방화벽 허용 (Ubuntu 기준)
sudo ufw allow 27015/udp
```

Oracle Cloud 콘솔에서도 VCN → Security List → Ingress Rules에서 **27015/UDP** 를 허용합니다.

---

## 2. 모드 적용법

### 2-1. mod.io API 키 발급

1. [mod.io](https://mod.io) 에 접속하여 계정을 만들거나 로그인합니다.
2. 우측 상단 프로필 → **API Access** 페이지로 이동합니다.
   - 직접 링크: `https://mod.io/me/access`
3. **API Keys** 섹션에서 **+ New API Key** 를 클릭합니다.
4. **Key Name**: 용도를 알 수 있는 이름 입력 (예: `ck-server`)
5. **Purpose**: `Application` 선택
6. **Agreement**: 동의 체크 후 **Submit**
7. 생성된 API 키를 복사합니다.

> mod.io의 Core Keeper 게임 페이지: https://mod.io/g/corekeeper

---

### 2-2. core.env에 API 키 및 모드 설정

`core.env` 파일에 아래 항목을 채웁니다:

```dotenv
MODS_ENABLED=true
MODIO_API_KEY=발급받은_API_키_입력
MODIO_API_URL=https://u-38332206.modapi.io/v1

# 설치할 모드 목록 (mod.io의 모드 Name ID를 쉼표로 구분)
MODS=allskills,double-chest-inventory,infinite-ore-boulders-dedicated-linux
```

### 2-3. 모드 Name ID 찾는 법

1. [mod.io Core Keeper 페이지](https://mod.io/g/corekeeper)에서 원하는 모드 검색
2. 모드 상세 페이지 URL의 마지막 부분이 **Name ID** 입니다.
   - 예: `https://mod.io/g/corekeeper/m/allskills` → Name ID: `allskills`

### 2-4. 특정 버전 고정 (선택)

모드를 최신 버전 대신 특정 버전으로 고정하려면 `모드ID:버전` 형식을 사용합니다:

```dotenv
MODS=allskills:1.2.3,double-chest-inventory
```

### 2-5. 모드 비활성화

모드 없이 바닐라 서버로 실행하려면:

```dotenv
MODS_ENABLED=false
```

### 2-6. 모드 업데이트 / 재설치

서버를 재시작하면 매번 모드를 재설치합니다.

```bash
docker compose restart
```

---

## 디렉토리 구조

```
core-keeper-arm-server/
├── Dockerfile              # 이미지 정의 (FEX-Emu + DepotDownloader)
├── docker-compose.yaml     # 서버 실행 설정
├── core.env                # 환경 변수 (직접 생성, Git 미포함)
├── core.env.example        # 환경 변수 템플릿
├── scripts/
│   └── init-server.sh      # 서버 초기화 및 실행 스크립트
└── data/                   # 월드 세이브, 설정 등 영구 데이터 (Git 미포함)
```

---

## 작동 방식

1. **FEX-Emu**: ARM64 호스트에서 x86-64 Core Keeper 서버 바이너리를 에뮬레이션
2. **DepotDownloader**: Steam에서 게임 서버 파일을 자동 다운로드 (첫 실행 시)
3. **mod.io API**: 지정한 모드를 서버 시작 시 자동 다운로드 및 설치
4. **CPU 최적화**: 서버 세션 시작 전까지 코어 0에 고정, 세션 시작 후 전체 코어(0-3) 개방

---

## 문제 해결

**서버가 시작되지 않는 경우**
```bash
docker logs ck-server 2>&1 | tail -50
```

**월드 데이터가 사라진 경우**
- `data/` 폴더가 `docker-compose.yaml`의 볼륨에 올바르게 마운트되어 있는지 확인

**모드 설치 실패**
- `MODIO_API_KEY`가 올바른지 확인
- 모드 Name ID가 정확한지 mod.io에서 재확인
- 서버 전용(Dedicated Server)을 지원하는 모드인지 확인
