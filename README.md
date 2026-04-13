---

## 🚀 Quick Start

### 1️⃣ Start Flask Backend (Profiles & Lists)

```bash
cd backend2
$env:FLASK_ENV = "development"
.venv\Scripts\python app.py
```

---

### 2️⃣ Set up and start VLM server (MAGIC)

#### Go into the VLM folder

```bash
cd "VLM Testing"
```

---

### Create and activate conda environment

```bash
conda create -n magic-vlm python=3.10 -y
conda activate magic-vlm
```

---

### Upgrade pip / setuptools / wheel

```bash
python -m pip install --upgrade pip setuptools wheel
```

---

### Check CUDA Version

```bash
nvidia-smi
```

---

### Install PyTorch (GPU)

```bash
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
```

---

### Install remaining requirements

```bash
pip install -r requirements.txt
pip install flask easyocr ultralytics
```

---

### Set environment variables

```bash
export VLM_MODEL_NAME="Qwen/Qwen3-VL-2B-Instruct" MAX_NEW_TOKENS=96 MAX_IMAGE_SIDE=768 SERIALIZE_VLM=1 OCR_GPU=0 YOLO_MODEL_PATH="best.pt" RETURN_TRACEBACK=1
```

---

### Start VLM server

```bash
python app_server_VLM.py
```

---

## 🌐 3️⃣ Start ngrok (Expose MAGIC server to internet)

Open a **new terminal on MAGIC**:

```bash
./ngrok http 5010
```

You will see something like:

```text
Forwarding https://abc123.ngrok-free.dev -> http://localhost:5010
```

👉 Copy the **HTTPS URL**

---

### Update Vercel Environment Variable

Set:

```text
OCR_PROXY_TARGET=https://abc123.ngrok-free.dev
```

Then **redeploy your Vercel app**.

---

### Test ngrok

Open:

```text
https://abc123.ngrok-free.dev/health
```

If it works → your backend is connected.

---

## 📱 4️⃣ Run Flutter app (from root folder)

### Local development (direct connection)

```bash
flutter clean
flutter pub get
flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010
```

---

### Deployed app (Vercel)

No need to pass `OCR_BASE_URL` — it will use the Vercel proxy + ngrok.

---

## 📱 Running on Different Devices

| Where you run the app       | Command                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| Web (Chrome)                | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010` |
| Android emulator            | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5010`                  |
| Physical phone (same Wi-Fi) | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5010`            |

---

## ⚠️ Important Notes

* ngrok must stay running:

  ```bash
  ./ngrok http 5010
  ```
* If ngrok stops → your deployed app will break
* Free ngrok URLs change every time you restart → update Vercel each time

---

## ⚙️ Architecture Overview

* **Flutter frontend**

  * UI + camera
  * TTS / STT

* **Flask backend (`backend2`)**

  * authentication (Supabase)
  * grocery lists + profiles

* **VLM server (`VLM Testing`)**

  * image understanding (Qwen3-VL)

* **EasyOCR**

  * aisle / sign text detection

* **YOLO (optional)**

  * shelf object detection

---

## ✨ Features

* Supabase authentication (login/signup)
* User profiles (allergies, dietary preferences)
* Grocery list management
* Voice input (TTS + STT)
* Aisle scanner (OCR)
* Shelf scanner (YOLO or VLM)
* Fully accessible UX with audio guidance

---
