# my_low_vision_app

A Flutter app for low-vision users that combines Supabase-backed grocery list management, guided aisle/shelf OCR shopping mode, voice-guided item entry (TTS + STT), and EasyOCR text extraction from the camera.

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) installed
- Python 3 with required packages (see steps below)
- A Supabase project (already configured — credentials are in `lib/main.dart`)
- Chrome browser for web

---

## How to Run the Program

### 1. Run the Flutter app

From the project root (`capstone_sp2026_lowVision`):

```bash
flutter pub get
flutter devices          # optional: list phones, emulators, Chrome, Windows, etc.
flutter run              # runs on the default device
```

**Common targets**

| Target | Command |
|--------|---------|
| Chrome (web) | `flutter run -d chrome` |
| Windows desktop | `flutter run -d windows` |
| Android (device or emulator) | `flutter run` *(pick the Android device if prompted)* |
| iOS Simulator / iPhone *(macOS only)* | `flutter run -d ios` or choose the device when prompted |

The first build can take a few minutes; hot reload works after the app starts (`r` in the terminal).

---

### 2. Flask backend (required for profiles / grocery API)

The app expects the Flask API on port **5000**. Start it in a **second terminal**:

**Windows (PowerShell)**

```powershell
cd capstone_sp2026_lowVision\backend2
$env:FLASK_ENV="development"
.\.venv\Scripts\python app.py
```

**macOS / Linux**

```bash
cd backend2
export FLASK_ENV=development
./.venv/bin/python app.py
```

> **First time only** — virtual environment and dependencies:
> ```bash
> cd backend2
> python -m venv .venv
> # Windows: .\.venv\Scripts\activate
> # macOS/Linux: source .venv/bin/activate
> pip install -r requirements.txt
> ```

You should see the server on `http://127.0.0.1:5000`.

---

### 3. OCR (text from camera)

By default the app sends images to the **MAGIC** OCR service (`POST …/extract-text`). You do **not** need a local OCR server unless you want offline / local EasyOCR.

**Run OCR on MAGIC server**

From the directory that contains `app_server_new.py`, restart with:

```bash
pkill -f app_server_new.py || true; python3 app_server_new.py
```

This kills any old process first, then starts the server on port `5010`.

**Local EasyOCR instead** — third terminal, from project root:

```bash
python ocr_server.py
```

> **First time only:** `pip install easyocr flask pillow numpy`  
> EasyOCR downloads models on first run (can take several minutes).

Then run Flutter with a base URL that points at your machine:

| Where you run the app | Example `dart-define` |
|------------------------|------------------------|
| Web (Chrome) | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://localhost:5001` |
| Android emulator | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5001` |
| Physical phone on same Wi‑Fi | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5001` |

Override MAGIC URL anytime with the same flag, e.g.  
`--dart-define=OCR_BASE_URL=https://your-server.example.com/base/path`.

---

## Quick checklist

| Step | When | Command |
|------|------|---------|
| 1. Flutter dependencies | Once per clone | `flutter pub get` |
| 2. Flask backend | Whenever you use lists / profiles | `cd backend2` → start `app.py` (see above) |
| 3. OCR | Optional — only for **local** EasyOCR | `python ocr_server.py` + `--dart-define=OCR_BASE_URL=...` |
| 4. Run the app | Every session | `flutter run` or `flutter run -d chrome` (etc.) |

---

## Features

- **Supabase authentication** — email/password signup and login
- **User profile** — set dietary preferences and allergies on signup; edit any time via the person icon
- **Grocery lists** — create, view, and delete lists per user
- **Grocery items** — add items manually or via voice (TTS guides you, STT captures your answer)
- **Aisle scanner shopping mode** — tap the cart icon on a list to start shopping:
  1. Point camera at the **aisle sign** → OCR detects which list items are in that aisle (read aloud via TTS)
  2. Point camera at the **shelf** → OCR detects items visible on the shelf
  3. Check off items, then move to the next aisle — list stays sorted in the order you walk the aisles
  4. Audio can be muted/unmuted at any time with the volume button
- **OCR camera** — point at any text and extract it with EasyOCR (camera icon on grocery lists screen)

---

## Server ports

| Server | Port |
|--------|------|
| Flask backend (user profiles) | 5000 |
| Local EasyOCR (`ocr_server.py`) | 5001 |
| Flutter dev server (web) | auto-assigned (e.g. random high port) |

Remote OCR uses the MAGIC host configured in `lib/ocr_config.dart` (no local port).

---

## Project resources

- [Flutter documentation](https://docs.flutter.dev/)
- [Supabase documentation](https://supabase.com/docs)
- [EasyOCR GitHub](https://github.com/JaidedAI/EasyOCR)
