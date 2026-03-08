# Core Keeper Dedicated Server (ARM64)

> **English** | [한국어](docs/README_kr.md)

A Docker image for running a Core Keeper dedicated server on **ARM64** hosts via [FEX-Emu](https://fex-emu.com/).

> **Supported:** ARM64 hosts (Oracle Cloud A1, Ampere, etc.)

---

## Prerequisites

- Docker & Docker Compose
- ARM64 host (Oracle A1 Flex, etc.)
- mod.io API key (if using mods)

---

## 1. Running the Server

### 1-1. Clone the Repository

```bash
git clone https://github.com/Hangeol-Chang/core-keeper-arm-server.git
cd core-keeper-arm-server
```

### 1-2. Configure Environment Variables

Copy the template and fill in your values:

```bash
cp core.env.example core.env
```

Edit `core.env`:

```dotenv
WORLD_NAME="My Server"          # Server / world name
MAX_PLAYERS=5                   # Maximum number of players
WORLD_INDEX=0                   # World slot (0~2)
SEASON=0                        # Season setting

GAME_ID=my-unique-server-id     # Unique server ID (Steam lobby identifier)
SERVER_PORT=27015               # Server port (UDP)
PASSWORD=your_password          # Server password (leave blank for none)
ALLOW_ONLY_PLATFORM=1           # 1: Steam only, 0: cross-platform
```

### 1-3. Create the Data Directory

```bash
mkdir -p data
```

### 1-4. Pull Image and Start Server

```bash
docker compose up -d
```

### 1-5. Check Logs

```bash
docker logs -f ck-server
```

The server is ready when you see:

```
Started session with info ...
```

### 1-6. Stop / Restart

```bash
docker compose down       # Stop
docker compose restart    # Restart
```

### Firewall / Port Configuration

If you are using Oracle Cloud, open port **27015/UDP** in both places:

```bash
# Ubuntu UFW
sudo ufw allow 27015/udp
```

Also add an **Ingress Rule** for **27015/UDP** in the OCI Console under VCN → Security List.

---

## 2. Using Mods

### 2-1. Get a mod.io API Key

1. Sign in (or create an account) at [mod.io](https://mod.io).
2. Go to your profile → **API Access**, or visit `https://mod.io/me/access` directly.
3. Under **API Keys**, click **+ New API Key**.
4. **Key Name**: anything descriptive (e.g., `ck-server`)
5. **Purpose**: `Application`
6. Accept the agreement and click **Submit**.
7. Copy the generated API key.

> Core Keeper page on mod.io: https://mod.io/g/corekeeper

---

### 2-2. Set API Key and Mod List in core.env

```dotenv
MODS_ENABLED=true
MODIO_API_KEY=your_api_key_here
MODIO_API_URL=https://u-38332206.modapi.io/v1

# Comma-separated list of mod Name IDs from mod.io
MODS=allskills,double-chest-inventory,infinite-ore-boulders-dedicated-linux
```

### 2-3. Finding a Mod's Name ID

The last segment of the mod's URL on mod.io is its **Name ID**:

```
https://mod.io/g/corekeeper/m/allskills  →  Name ID: allskills
```

### 2-4. Pin a Specific Version (Optional)

Use `nameID:version` syntax to lock a mod to a specific version:

```dotenv
MODS=allskills:1.2.3,double-chest-inventory
```

### 2-5. Disable Mods

To run a vanilla server without any mods:

```dotenv
MODS_ENABLED=false
```

### 2-6. Update / Reinstall Mods

Mods are reinstalled on every server start. Simply restart to pick up updates:

```bash
docker compose restart
```

---

## Directory Structure

```
core-keeper-arm-server/
├── Dockerfile              # Image definition (FEX-Emu + DepotDownloader)
├── docker-compose.yaml     # Server runtime configuration
├── core.env                # Your environment variables (not committed)
├── core.env.example        # Environment variable template
├── scripts/
│   └── init-server.sh      # Server initialization & launch script
├── docs/
│   └── README_kr.md        # Korean documentation
└── data/                   # World saves & persistent data (not committed)
```

---

## How It Works

1. **FEX-Emu** — Emulates the x86-64 Core Keeper server binary on an ARM64 host.
2. **DepotDownloader** — Downloads the game server files from Steam on first run.
3. **mod.io API** — Downloads and installs specified mods on each server start.
4. **CPU Pinning** — Server starts pinned to core 0; all cores (0–3) are unlocked after the session initialises.

---

## Troubleshooting

**Server won't start**
```bash
docker logs ck-server 2>&1 | tail -50
```

**World data missing**
- Verify the `data/` directory is correctly mounted as a volume in `docker-compose.yaml`.

**Mod installation fails**
- Confirm `MODIO_API_KEY` is valid.
- Double-check Name IDs on mod.io.
- Ensure the mod supports dedicated servers.
