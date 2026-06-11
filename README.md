# PrivateClipServer
This is a Dockerized file server that uses a WireGuard VPN to share video clips privately, with some custom scripts functions.

> A self-hosted, VPN-gated file server with automatic video transcoding and a live progress bar. Upload files securely from anywhere through a WireGuard VPN tunnel, manage them via a web UI, and let the server automatically transcode your videos to a web-compatible format.

```
                        ┌────────────────────────────────────────────────┐
                        │              Docker Host                       │
                        │                                                │
  Client (VPN)          │  ┌──────────┐     ┌───────────────────────┐    │
  ┌──────────┐          │  │WireGuard │     │       Watchers        │    │
  │WireGuard │◄─UDP────►│  │  :51820  │     │  video_processor      │    │
  │  Client  │          │  │ 10.0.0.1 │     │  keys_watcher         │    │
  └────┬─────┘          │  └───┬──────┘     └──────────┬────────────┘    │
       │                │      │ (shared network ns)   └───┐             │
       │                │      │                           │             │
       │ HTTP           │  ┌───┴──────────────────────┐    │ ffmpeg      │
       │ 10.0.0.1:8080  │  │        Nginx             │    ▼             │
       └───────────────►│  │  :8080 (reverse proxy)   │  /data/raw       │
                        │  │ + JS inject(progress bar)│    │             │
                        │  └────────┬─────────────────┘    ▼             │
                        │           │                    /data/processed │
                        │  ┌────────┴──────────────────┐ + status.json   │
                        │  │       FileBrowser         │                 │
                        │  │  :8081 (file manager UI)  │                 │
                        │  └───────────────────────────┘                 │
                        └────────────────────────────────────────────────┘
```
---

## Table of Contents

1. [Overview](#1-overview)
2. [How It Works](#2-how-it-works)
3. [How the Video Pipeline Works](#3-how-the-video-pipeline-works)
4. [The Corruption-Fix Algorithm Explained](#4-the-corruption-fix-algorithm-explained)
5. [Requirements](#5-requirements)
6. [Installation](#6-installation)
   - 6.1 [Windows — Setting up WSL2](#61-windows--setting-up-wsl2)
   - 6.2 [Linux — Direct setup](#62-linux--direct-setup)
7. [Usage Guide](#7-usage-guide)
   - 7.1 [Task: First Boot — Start the Server](#71-task-first-boot--start-the-server)
   - 7.2 [Task: Register a New Client (Server)](#72-task-register-a-new-client-in-server)
   - 7.3 [Task: Connect a Client — Windows](#73-task-connect-a-client--windows)
   - 7.4 [Task: Connect a Client — Linux / macOS](#74-task-connect-a-client--linux--macos)
   - 7.5 [Task: Connect a Client — Mobile (QR)](#75-task-connect-a-client--mobile-qr)
   - 7.6 [Task: Upload and Access Files](#76-task-upload-and-access-files)
   - 7.7 [Task: Process a Video](#77-task-process-a-video)
   - 7.8 [Task: Restart / Reset the Server](#78-task-restart--reset-the-server)
8. [Reference: Ports & IPs](#8-reference-ports--ips)
9. [Reference: Project Structure](#9-reference-project-structure)
10. [Troubleshooting](#10-troubleshooting)
11. [License](#11-license)

---

## 1. Overview

PrivateClipServer turns any Linux machine (or a Windows machine via WSL2) into a private, VPN-protected file server with automatic video transcoding. Access is restricted exclusively to devices connected through a WireGuard VPN tunnel — the web interface is never exposed directly to the internet.

**Key features:**

- **VPN-gated access** — FileBrowser is only reachable from inside the WireGuard tunnel. No credentials are exposed to the open internet.
- **Automatic peer registration** — Drop a client's public key as a `.txt` file into `data/keys_inbox/` and the server registers it automatically, no manual editing of config files needed.
- **Automatic video transcoding** — Upload any `.mp4`, `.mkv`, `.mov` or `.avi` to `raw/` and a transcoded, web-compatible version appears in `processed/` automatically.
- **Live progress bar** — A real-time encoding progress bar is injected into the FileBrowser UI via Nginx, showing filename, percentage, ETA, speed, and a queue of pending videos.
- **Corruption-tolerant encoding** — Videos from sources like Nvidia Instant Replay that cut mid-GOP are automatically repaired before transcoding using a Remux-Trim scan strategy.
- **Single-command startup** — One `bash main_use.sh` brings up all four services.
- **Cross-platform clients** — Client setup scripts available for Windows, Linux/macOS, and mobile (QR code).

---

## 2. How It Works

The system is composed of four Docker containers that share volumes and, where relevant, a network namespace.

### WireGuard

The only container with a public-facing port (`51820/UDP`). It acts as the VPN server and as the **network gateway for the entire stack**. Nginx and FileBrowser both share WireGuard's network namespace (`network_mode: service:wireguard`), meaning all traffic to `10.0.0.1:8080` flows through WireGuard's interface — unreachable from the open internet.

### Nginx

A reverse proxy sitting between the VPN interface and FileBrowser. It listens on `:8080` and forwards requests to FileBrowser on `:8081`. Beyond proxying, it performs two additional tasks:

- **Progress bar injection** — It intercepts FileBrowser's HTML response and injects a `<script>` tag just before `</body>`, loading `injection_custom_progress_bar.js`. This script polls `/status/status.json` every 2 seconds and renders a live encoding progress bar at the bottom of the UI.
- **Status file serving** — It exposes `/status/status.json` from `/data/processed/`, with `Cache-Control: no-store` headers to ensure the browser always reads the latest state. If the file doesn't exist (no encoding in progress), it returns `{"active": false}` instead of a 404.

### FileBrowser

A web UI served internally at `:8081`. Clients use it to upload files to `raw/` and browse files in `processed/`. On first run it generates a random admin password printed in the container logs.

### Watchers

A container running three background daemons in parallel:

- **`keys_watcher.sh`** — Monitors `data/keys_inbox/` using `inotifywait`. When a `.txt` file appears, it reads the WireGuard public key inside, calls `add_peer.sh` to append the new `[Peer]` block to `wg0.conf`, and restarts the WireGuard, FileBrowser, and Nginx containers to apply the change. The `.txt` file is deleted after processing.

- **`video_processor_watcher.sh`** — Monitors `data/raw/` using `inotifywait`. When a video file is fully written (`close_write` event), it validates the file with `ffprobe` (guards against incomplete uploads) and adds it to a file-based queue in `/tmp/pcs_queue/`.

- **`queue_processor.sh`** — Continuously polls the queue and processes one video at a time. For each video it runs the corruption scan, then encodes via `ffmpeg`, and writes real-time progress to `/data/processed/status.json` via `progress_bar_writer.sh`.

---

## 3. How the Video Pipeline Works

```
  Client uploads file via FileBrowser
             │
             │  (close_write event)
             ▼
      /data/raw/<filename>
             │
             │  video_processor_watcher.sh
             │  ffprobe validates moov atom
             │  (incomplete uploads are skipped)
             ▼
      /tmp/pcs_queue/<timestamp>_pending
             │
             │  queue_processor.sh picks next entry
             ▼
   ┌─────────────────────────────┐
   │   Corruption Scan Loop      │  ← see section 4
   │   (remux + test-decode      │
   │    second by second)        │
   └─────────────┬───────────────┘
                 │  ENCODE_INPUT = clean start point
                 │
                 ├──────────────────────────────────┐
                 │                                  │
                 ▼                                  ▼
    progress_bar_writer.sh               ffmpeg encode
    polls ffmpeg -progress pipe          libx264, CRF 23
    writes status.json every 2s         AAC 192k, yuv420p
                 │                                  │
                 ▼                                  │
    /data/processed/status.json                     │
                 │                                  │
                 │  Nginx serves it                 │
                 ▼                                  │
    Browser JS polls every 2s                       │
    → renders progress bar in UI                    │
                                                    ▼
                                   /data/processed/<name>_(processed).mp4
```

**Queue behaviour:** If a second video is uploaded while the first is still encoding, it is added to the queue and its name appears in the "queued" widget on the progress bar. Videos are processed in upload order (FIFO). The queue is file-based (`/tmp/pcs_queue/`) so it survives small interruptions within the container lifetime.

**Atomic writes:** `status.json` is never written directly. All writes go to `status.json.tmp` first, then renamed atomically. This prevents the browser from reading a half-written, invalid JSON file mid-update.

**Transcoding settings applied:**

| Parameter | Value | Notes |
|---|---|---|
| Video codec | `libx264` | Widely compatible H.264 |
| CRF | `23` | Good quality/size balance (lower = better quality) |
| Preset | `medium` | Encoding speed vs compression ratio |
| Audio codec | `aac` | Standard audio format |
| Audio bitrate | `192k` | Good audio quality |
| Pixel format | `yuv420p` | Maximum browser and media player compatibility |
| Corrupt frames | `-fflags +discardcorrupt` | Discards remaining bad frames gracefully |
| Audio tracks | `-map 0` | Preserves all audio tracks |

---

## 4. The Corruption-Fix Algorithm Explained

### Background: why some clips are corrupted

This problem was designed and tested specifically against **Nvidia Instant Replay** clips, but applies to any recorder that saves from a circular buffer.

H.264 video is not a sequence of independent images. It is organized into **GOPs (Groups of Pictures)**:

```
GOP                  GOP
 │                    │
 ▼                    ▼
[I]─[P]─[B]─[P]─[B]─[I]─[P]─[B]─[P]─[B]─...
 │    │    │
 │    │    └── B-frame: encoded using both previous AND next I/P as reference
 │    └─────── P-frame: encoded using only the previous I or P as reference
 └──────────── I-frame: full image, no references — the only safe seek point
```

When Instant Replay saves a clip by cutting from a circular buffer, it often cuts **mid-GOP** — meaning the clip starts with P or B frames that reference an I-frame that is **not in the file**. This causes `cabac_init_idc` overflows, invalid NAL units, and FMO/data-partitioning errors.

### Why a simple `-ss` seek doesn't work

An MP4 file has an **`avcC` atom** in its container header. This atom stores the SPS (Sequence Parameter Set) and PPS (Picture Parameter Set) — the global decoding parameters that `ffmpeg` reads **at file-open time**, before any frame is touched.

When the clip was cut mid-GOP, the `avcC` is often corrupted too. This means **`ffmpeg`'s decoder is poisoned the moment it opens the file**, making any `-ss` seek useless — the decoder is already broken.

```
Normal file:      [avcC: valid] ──► ffmpeg opens ──► seeks ──► decodes OK
Corrupted clip:   [avcC: broken] ──► ffmpeg opens ──► decoder poisoned ──► seek fails
```

### Previous failed approaches

| Attempt | Strategy | Why it failed |
|---|---|---|
| `_3.sh` | Use `ffprobe` to find the first I-frame and seek to it | `avcC` corrupts the decoder at open time, before the seek |
| `_2.sh` | Decode 0.5s chunks and count errors | Slow and unreliable — chunk boundaries did not align with GOPs |

### The current solution: Remux-Trim scan

The key insight is: if you **remux** (stream-copy) from a specific time position, `ffmpeg` generates a **brand-new `avcC`** based only on the frames starting at that position — completely independent of the original corrupted header.

```
for PROBE_T in 0, 1, 2, 3, ... (seconds):

  Step 1 — Remux from PROBE_T into a temp file (no re-encode, instant):
  ┌─────────────────────────────────────────────────────────────┐
  │  ffmpeg -ss $PROBE_T -i input.mp4 -c copy TEST_FILE.mp4     │
  │                                                             │
  │  Result: TEST_FILE has a FRESH avcC built from this         │
  │  position forward — the original poisoned header is gone.   │
  └─────────────────────────────────────────────────────────────┘

  Step 2 — Test-decode the fresh file (2s window, 60 frames max):
  ┌─────────────────────────────────────────────────────────────┐
  │  ERROR_LINES=$(ffmpeg -v error -t 2.0 -i TEST_FILE          │
  │    -frames:v 60 -f null /dev/null 2>&1 | wc -l)             │
  │                                                             │
  │  if ERROR_LINES == 0:                                       │
  │    → Clean GOP found at PROBE_T seconds                     │
  │    → Use TEST_FILE as encode input and break                │
  │  else:                                                      │
  │    → Still corrupted, try PROBE_T + 1                       │
  └─────────────────────────────────────────────────────────────┘
```

**Cost:** One fast remux per second of corruption. For a clip with 3 corrupt seconds, that is 3 cheap stream-copies before a clean start is found. The tradeoff is intentional: slow but immune to `avcC` poisoning.

**During the scan**, the progress bar widget shows a `🔍 Scanning for corruption… pos Xs` state so the user knows what is happening.

**If no clean position is found** (entire file is undecodable), the encoder falls back to the original file with `-fflags +discardcorrupt` to at least produce something.

---

## 5. Requirements

### Server

| Requirement | Notes |
|---|---|
| Docker Engine | With the Docker Compose v2 plugin (`docker compose`, not `docker-compose`) |
| Linux kernel with WireGuard support | Ubuntu 22.04 recommended. On Windows, use WSL2 (see section 6.1) |
| Open port `51820/UDP` | Must be forwarded in your router/NAT to the server machine |

### Clients

| Requirement | Notes |
|---|---|
| [WireGuard](https://www.wireguard.com/install/) | Available for Windows, Linux, macOS, Android, iOS |
| `qrencode` | Only for mobile QR setup — `sudo apt install -y qrencode` |

---

## 6. Installation

### 6.1 Windows — Setting up WSL2

If you are on Windows, the server runs inside a WSL2 Ubuntu machine. A setup script automates the entire process.

1. Right-click `setup/build_wsl_ubuntu_machine.bat` and select **Run as administrator**.

2. The script will automatically:
   - Set your machine's IP to `192.168.1.50/24` (gateway `192.168.1.1`, DNS `1.1.1.1`). Adjust the script if your network uses a different range.
   - Install an **Ubuntu 22.04** WSL2 machine.
   - Create a `.wslconfig` with `networkingMode=mirrored` so the WSL machine shares the host's IP.
   - Add Windows Firewall rules to allow traffic on ports `8080/TCP` and `51820/UDP`.
   - Install `docker-compose-v2` inside the WSL machine.

3. When the Ubuntu installer opens in a new window, create your UNIX username and password, then type `exit`.

4. Once the script finishes, open the Ubuntu-22.04 terminal and clone the repository:

```bash
git clone https://github.com/Penguin1866s/PrivateClipServer
cd PrivateClipServer
```

> **To undo everything:** cleanup commands are commented at the bottom of `setup/build_wsl_ubuntu_machine.bat`.

---

### 6.2 Linux — Direct setup

1. Install Docker and Docker Compose v2:

```bash
sudo apt update && sudo apt install -y docker-compose-v2
```

2. Clone the repository:

```bash
git clone https://github.com/Penguin1866s/PrivateClipServer
cd PrivateClipServer
```

3. Forward port `51820/UDP` to your machine in your router. That's it — no other configuration is needed before the first boot.

---

## 7. Usage Guide

### 7.1 Task: First Boot — Start the Server

From the project root, run:

```bash
bash main_use.sh
```

This builds the four Docker images and starts the containers in detached mode. On subsequent runs it reuses cached images unless code has changed.

The script also prints everything you need to share with clients:

```
==========================================
FOR CLIENTS:
==========================================

The first admin password:
<randomly generated password>

Public Key of Server:
<base64 wireguard public key>

The last ip client assigned:
10.0.0.1/32

The public ip Server:
<your public IP>
```

> **Save the admin password.** It is only printed once on first boot. If you lose it, see the [Troubleshooting](#10-troubleshooting) section.

---

### 7.2 Task: Register a New Client in server

When a new client wants to connect, they need to share their WireGuard **public key** with you (generated by the client scripts in sections 7.3–7.5). Once you have it:

1. Create a plain `.txt` file containing only the public key:

```bash
echo "CLIENT_PUBLIC_KEY_HERE" > data/keys_inbox/new_client.txt
```

Or create the file through the FileBrowser web UI — it monitors the same folder.

2. The `keys_watcher` daemon detects the file instantly and:
   - Assigns the next available IP in the `10.0.0.x/24` range.
   - Appends the peer block to `data/wireguard_config/wg0.conf`.
   - Restarts WireGuard, FileBrowser, and Nginx containers to apply the change.
   - Deletes the `.txt` file automatically.

3. Tell the client which IP they were assigned. You can check the last assigned IP with:

```bash
sudo docker exec privateclipserver_wireguard cat /etc/wireguard/wg0.conf | grep -oP "AllowedIPs = \K.*" | tail -n1
```

> Clients are assigned IPs sequentially: first client gets `10.0.0.2`, second gets `10.0.0.3`, and so on.

4. And to apply the new config, restart the server (see [section 7.8](#78-task-restart--reset-the-server) for details).
---

### 7.3 Task: Connect a Client — Windows

**Prerequisites:** [WireGuard for Windows](https://www.wireguard.com/install/) installed in the default path (`C:\Program Files\WireGuard\`).

1. Run `client/client_windows.bat` (double-click or run from a terminal).

2. Answer the four prompts:
   - **Name of the new tunnel connection** — any name, e.g. `myprivateclip`
   - **Public Key of the Server** — from the server's `main_use.sh` output
   - **Private IP for this client** — the IP the admin assigned, e.g. `10.0.0.2/24`
   [!NOTE] is the _The last ip client assigned:_ of the main_use.sh output, e.g. output of _The last ip client assigned:_ '10.0.0.1/32' sum +1 to the last octet, and substitute the /32 with /24, result: `10.0.0.2/24`.
   - **Server public IP** — your server's public IP

3. A `<tunnel_name>.conf` file is created in the same folder.

4. Open WireGuard → click **Import tunnel from file** → select the `.conf` file.

5. The script also prints your **client public key** — send it to the admin for registration (section 7.2).

6. Once the admin confirms registration, click **Activate** in WireGuard.

7. Open a browser and go to `http://10.0.0.1:8080` to access FileBrowser.

---

### 7.4 Task: Connect a Client — Linux / macOS

**Prerequisites:** `wireguard-tools` installed.

```bash
# Ubuntu/Debian
sudo apt install -y wireguard-tools

# macOS
brew install wireguard-tools
```

1. Run the client script:

```bash
bash client/client_linux.sh
```

2. Answer the four prompts (same as the Windows version).

3. A `<tunnel_name>.conf` file is created in the current directory.

4. Move it to the WireGuard config folder and activate the tunnel:

```bash
sudo mv <tunnel_name>.conf /etc/wireguard/
sudo wg-quick up <tunnel_name>
```

5. Send the printed **client public key** to the admin for registration (section 7.2).

6. Once confirmed, the tunnel is already active. Access FileBrowser at `http://10.0.0.1:8080`.

To disconnect:
```bash
sudo wg-quick down <tunnel_name>
```

---

### 7.5 Task: Connect a Client — Mobile (QR)

**Prerequisites:** `qrencode` installed on the machine generating the QR, and the **WireGuard app** on your phone ([Android](https://play.google.com/store/apps/details?id=com.wireguard.android) / [iOS](https://apps.apple.com/app/wireguard/id1441195209)).

```bash
sudo apt install -y qrencode
```

1. Run the mobile script (it wraps `client_linux.sh` and generates a QR code):

```bash
bash client/client_mobile_qr.sh
```

2. Answer the four prompts.

3. A QR code is rendered in the terminal. Open the WireGuard app on your phone → tap **+** → **Scan from QR Code** → scan it.

4. The `.conf` file is automatically deleted after the QR is shown.

5. Send the printed **client public key** to the admin for registration (section 7.2).

6. Once confirmed, activate the tunnel in the WireGuard app and browse to `http://10.0.0.1:8080`.

---

### 7.6 Task: Upload and Access Files

**Prerequisite:** VPN tunnel active (sections 7.3 / 7.4 / 7.5).

1. Open a browser and go to: `http://10.0.0.1:8080`

2. Log in with the admin credentials printed on first boot.

3. You will see three main folders:
   - **`raw/`** — upload original videos here to trigger automatic transcoding.
   - **`processed/`** — transcoded videos appear here automatically.
   - **`keys_inbox/`** — admin use only: drop `.txt` files here to register new VPN peers.

4. Use FileBrowser's upload button to upload files. Multiple files and drag-and-drop are supported.

> **Note:** FileBrowser is exclusively accessible from the VPN (`10.0.0.x` network). It cannot be reached from the open internet — this is by design.

---

### 7.7 Task: Process a Video

Automatic — no manual steps needed once the file is uploaded.

1. Upload a video file in any of these formats to the `raw/` folder: `.mp4`, `.mkv`, `.mov`, `.avi`.

2. The `video_processor_watcher` detects the completed upload, validates it, and adds it to the queue.

3. The `queue_processor` picks it up, runs the corruption scan (see [section 4](#4-the-corruption-fix-algorithm-explained)), and starts transcoding.

4. A **live progress bar** appears at the bottom of the FileBrowser UI showing the current file, percentage, elapsed time, ETA, encoding speed, and any queued files.

5. Once done, a new file named `<original_name>_(processed).mp4` appears in `processed/`.

> The original file in `raw/` is kept untouched. Processing time depends on file size and the server's CPU.

---

### 7.8 Task: Restart / Reset the Server

**Soft restart** — applies config changes, keeps all data and images:
```bash
sudo docker compose restart
```

**Full rebuild** — rebuilds images from Dockerfiles, keeps all data:
```bash
sudo docker compose up -d --build
```

**Stop without removing** — stops containers, keeps images and data:
```bash
sudo docker compose down
```

**Full wipe** — removes containers, images and orphans. Data in `./data/` is NOT deleted:
```bash
sudo docker compose down --rmi all --remove-orphans
```

> ⚠️ **Warning:** `data/wireguard_config/` contains the server's WireGuard private key and `wg0.conf`. If you delete this folder, a new key pair is generated on next boot and **all existing clients will need to reconnect** with the new server public key.

---

## 8. Reference: Ports & IPs

### Ports

| Port | Protocol | Service | Accessible from |
|---|---|---|---|
| `51820` | UDP | WireGuard VPN | Internet — must be forwarded in your router |
| `8080` | TCP | Nginx → FileBrowser web UI | VPN only (`10.0.0.x` network) |
| `8081` | TCP | FileBrowser (internal only) | Container network only — never exposed externally |

### IP Addresses

| Address | Description |
|---|---|
| `10.0.0.1` | Server — VPN internal IP |
| `10.0.0.2` | First registered client |
| `10.0.0.3` | Second registered client |
| `10.0.0.x` | Each new client gets the next available IP in sequence |

### URLs

| URL | Description |
|---|---|
| `http://10.0.0.1:8080` | FileBrowser web UI via Nginx (VPN required) |
| `<server_public_ip>:51820` | WireGuard VPN endpoint |

---

## 9. Reference: Project Structure

```
privateclipserver/
│
├── docker-compose.yml              # Defines the 4 services
├── main_use.sh                     # Build, start, and print client info
│
├── services/                       # Docker build contexts
│   │
│   ├── wireguard/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh           # Generates keys + wg0.conf on first run, starts wg-quick
│   │
│   ├── nginx/
│   │   ├── Dockerfile
│   │   ├── nginx.conf              # Reverse proxy to FileBrowser :8081 + /status/ route
│   │   └── injection_custom_progress_bar.js  # Injected into FileBrowser HTML by Nginx
│   │                                          # Polls /status/status.json every 2s
│   │                                          # Renders progress bar + queue widget
│   │
│   ├── filebrowser/
│   │   └── Dockerfile              # Installs FileBrowser, listens on :8081
│   │
│   └── watchers/
│       ├── Dockerfile              # Installs ffmpeg, inotify-tools, docker.io
│       ├── entrypoint.sh           # Launches all three watchers in parallel
│       ├── keys_watcher.sh         # inotifywait on keys_inbox/, calls add_peer.sh
│       ├── add_peer.sh             # Appends [Peer] block to wg0.conf, restarts containers
│       ├── video_processor_watcher.sh  # inotifywait on raw/, adds entries to pcs_queue
│       ├── queue_processor.sh      # Processes queue: corruption scan + ffmpeg encode
│       └── progress_bar_writer.sh  # Reads ffmpeg -progress pipe, writes status.json
│
├── client/                         # Run these on client machines, not the server
│   ├── client_linux.sh             # Generates WireGuard .conf for Linux/macOS
│   ├── client_windows.bat          # Generates WireGuard .conf for Windows
│   └── client_mobile_qr.sh         # Wraps client_linux.sh and prints a QR code
│
├── setup/                          # Host machine preparation — run once
│   └── build_wsl_ubuntu_machine.bat  # Automated WSL2 + Docker setup for Windows hosts
│
└── data/                           # Runtime volumes — not versioned (git-ignored)
    ├── raw/                        # ← Upload videos here → triggers transcoding
    ├── processed/                  # ← Transcoded videos appear here automatically
    │                               #   Also contains status.json (written by watchers,
    │                               #   served by Nginx, polled by the browser widget)
    ├── keys_inbox/                 # ← Drop .txt with public key → auto-registered as VPN peer
    ├── wireguard_config/           # wg0.conf, privatekey, publickey — ⚠️ keep private!
    └── filebrowser_config/         # FileBrowser database (filebrowser.db) and settings
```

---

## 10. Troubleshooting

### FileBrowser is not accessible at `http://10.0.0.1:8080`

- Confirm the VPN tunnel is active on the client (`wg show` on Linux, green indicator on Windows/mobile).
- Confirm all four containers are running: `sudo docker ps`
- Check that Nginx, FileBrowser, and WireGuard share the network namespace — FileBrowser and Nginx should have no ports of their own in `docker ps`; only WireGuard should expose `8080` and `51820`.

### The progress bar never appears

- Check Nginx logs: `sudo docker logs privateclipserver_nginx`
- Make sure `sub_filter` is working — it requires `proxy_set_header Accept-Encoding ""` in `nginx.conf` to disable upstream compression. If FileBrowser sends gzip, Nginx cannot do string substitution.
- Verify the `/status/` location in `nginx.conf` points to `/data/processed/` and that the volume is correctly mounted in the Nginx container.

### WireGuard tunnel connects but there is no traffic

- Verify that `net.ipv4.ip_forward=1` is active inside the WireGuard container (set via `sysctls` in `docker-compose.yml`).
- Check the `iptables` MASQUERADE rule in `services/wireguard/entrypoint.sh` — the output interface is hardcoded as `eth0`. If your Docker bridge network uses a different interface name, update that line accordingly.

### A key was dropped in `keys_inbox/` but was not registered

- Check that the Watchers container is running: `sudo docker logs privateclipserver_watchers`
- Ensure the `.txt` file contained **only** the public key with no extra spaces, blank lines, or special characters.
- Verify that `inotifywait` is available inside the container — it is installed via the Watchers Dockerfile.

### Video is not being processed

- Confirm the file extension is one of: `.mp4`, `.mkv`, `.mov`, `.avi`. Other extensions are intentionally ignored.
- Check the watcher logs: `sudo docker logs privateclipserver_watchers`
- The watcher listens for `close_write`, which fires when the upload is fully complete. Partial uploads are skipped intentionally.
- If the file is valid but transcoding never starts, check that the queue directory `/tmp/pcs_queue/` is writable inside the Watchers container.

### Video is processed but the output is shorter than the original

- This is expected behavior when the corruption scan finds that the first few seconds of the video are undecodable. The output starts from the first clean GOP position. See [section 4](#4-the-corruption-fix-algorithm-explained) for details.

### I lost the admin password for FileBrowser

Run this to check if the password is still in the logs:

```bash
sudo docker logs privateclipserver_filebrowser 2>&1 | grep -oP "password: \K.*"
```

If not found, to change the password run the following commands:

```bash
# Change filebrowser admin password to "TheNewPassword".
sudo docker compose down
sudo docker run --rm \
  -v $(pwd)/data/filebrowser_config:/config \
  privateclipserver-filebrowser \
  filebrowser users update admin --password "TheNewPassword" \
  -d /config/filebrowser.db
sudo docker compose up -d
# NOTE: This command is saved in the bash history.
# You can delete it with "history -d $(history 1 | awk '{print $1}')"
```

> [!WARNING]
> The new password must be at least 12 characters long.

### A client needs to reconnect after a server restart

This is expected if `data/wireguard_config/` was deleted or the server's key pair was regenerated. The client must create a new `.conf` with the updated server public key and re-register their own public key with the admin.

---

## 11. License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](./LICENSE) for the full text.

> _Summary: you may use, study, modify and redistribute it, but if you run a modified version as a network service, you must offer that service's users the corresponding source code under the same license._