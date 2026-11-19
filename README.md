# NetEase Musician Upload Skill (`netease-musician-upload`)

Zero-focus, zero-popup, log-in-once AI Agent Skill for preparing audio/cover assets and uploading or publishing tracks to **NetEase Cloud Music Musician** (网易音乐人 / 网易云音乐人, `music.163.com/musician`).

---

## Key Features

- **Log in once, reuse forever**: Launches and reuses a dedicated persistent Chrome profile (`~/.chrome-agent-profile` on CDP port `9223`), isolated from your daily Chrome browser.
- **Zero consent popups & zero focus stealing**:
  - Dedicated `--user-data-dir` exposes standard `/json/version` and CDP WebSocket without triggering Chrome 144+ per-connection *"Allow remote debugging"* prompts.
  - Creates background tabs (`Target.createTarget({ background: true })`), injects audio/cover files directly via `DOM.setFileInputFiles`, and never calls `Target.activateTarget` or `Page.bringToFront`.
- **Pre-flight audio & cover preparation**:
  - Checks audio specs with `ffprobe` against NetEase Musician requirements (`MP3` / `WAV`, `>= 320 kbps`, `>= 44.1 kHz`, `< 200 MB`) and converts non-compliant files (e.g., `.m4a`/Opus) to `48 kHz / 16-bit` stereo WAV via `ffmpeg`.
  - Reads embedded Suno clip IDs via `suno` MCP (`audio-retrieve`) when present to auto-populate instrumental/style metadata and inspect/reuse cover art (`>= 640×640`), or generate a clean square cover via `dreamina` CLI.
- **Battle-tested DOM mappings & pitfall fixes**:
  - Targets stable `[data-schemaform-field="..."]` attributes instead of brittle positional `.ant-select` indices.
  - Handles `#albuminfobar` CDP mouse clicks, cover cropper modal confirmation, `originInfo` Popconfirm animation clicks, auto-prefixed special-artist-name validation cleanup, mandatory promo note text, and scoped audio upload progress polling.
- **Built-in legal & identity safety boundary**:
  - Automatically pauses at the final `.../authorization` step (`《作品上传使用许可书》` + SMS verification code), takes a screenshot for review, and waits for explicit human confirmation rather than signing binding contracts or bypassing SMS verification.

---

## Installation

### Using `skills` CLI

```bash
npx skills add Ouyang-Yu/netease-musician-upload
```

### Manual Clone

```bash
git clone https://github.com/Ouyang-Yu/netease-musician-upload.git ~/.agents/skills/netease-musician-upload
```

---

## Prerequisites

- **Google Chrome** or **Chromium** (macOS `/Applications/Google Chrome.app` or Linux `google-chrome` / `chromium`; override via `CHROME_BIN`)
- **Node.js 22+** (native `WebSocket` client for CDP)
- **`ffmpeg` & `ffprobe`** (audio validation and transcoding)
- **`curl`** (CDP readiness check in `scripts/ensure_chrome.sh`)
- *Optional*: `suno` MCP server (for Suno clip metadata/cover retrieval) and `dreamina` CLI (for AI cover generation)

---

## Repository Layout

```text
netease-musician-upload/
├── SKILL.md                  # Agent skill instructions, field mappings & safety rules
├── scripts/
│   └── ensure_chrome.sh      # Idempotent background Chrome launcher (~/.chrome-agent-profile:9223)
├── README.md                 # Documentation & installation guide
├── LICENSE                   # MIT License
└── .gitignore
```

---

## Usage

Once installed, simply ask your coding agent to upload or publish a track to NetEase Musician (e.g., *"帮我把 ~/Downloads/demo.m4a 上传到网易音乐人"*):

1. The agent runs `scripts/ensure_chrome.sh` to start/reuse the isolated persistent Chrome on port `9223`.
2. On the very first run, log in to `music.163.com/musician` once inside that dedicated browser window; future sessions reuse the saved login silently.
3. The agent prepares audio/cover assets, fills the album and track form in the background, and pauses at `.../authorization` for your final confirmation and SMS code.

---

## Disclaimer & License

- This skill is intended solely for legitimate musicians and creators managing their own accounts and authorized works on NetEase Cloud Music Musician.
- Users remain responsible for verifying copyright/AI disclosure accuracy and completing legal license agreements and SMS verification personally.
- Licensed under the [MIT License](./LICENSE).
