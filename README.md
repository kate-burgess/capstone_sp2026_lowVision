# 🛒 my_low_vision_app

A Flutter app designed for low-vision users, combining **grocery list management**, **aisle/shelf scanning**, and **voice-guided interaction** powered by VLM + OCR.

---

## 🚀 Quick Start

## 👉 Choose how you want to run the app:

### 🟢 Option A: Run Locally (fastest, no ngrok)

* Runs everything on your machine
* Best for development

👉 Go to **Steps 1,2,4 (Local Setup)**

---

### 🔵 Option B: Use Deployed App (Vercel)

* Uses hosted frontend on Vercel
* Requires ngrok to connect MAGIC backend

👉 Follow **Steps 1 → 3**

---

## 1️⃣ Start Flask Backend (Profiles & Lists)

```bash
cd backend2
$env:FLASK_ENV = "development"
.venv\Scripts\python app.py
```

---

## 2️⃣ Set up and Start VLM Server (MAGIC)

```bash
cd "VLM Testing"

conda create -n magic-vlm python=3.10 -y
conda activate magic-vlm

python -m pip install --upgrade pip setuptools wheel
```

---

## ⚙️ PyTorch + CUDA Setup (IMPORTANT)

### Check CUDA Version

```bash
nvidia-smi
```

Look for:

```
CUDA Version: 12.8
```

👉 Use this to pick the correct PyTorch version

---

### Install PyTorch (GPU)

👉 [https://pytorch.org/get-started/locally/](https://pytorch.org/get-started/locally/)

Example:

```bash
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
```

---

### ⚡ (Optional) Flash Attention

```bash
pip install flash-attn --no-build-isolation
```

Prebuilt wheels:
[https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/](https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/)

---

### Install Remaining Requirements

```bash
pip install -r requirements.txt
pip install flask easyocr ultralytics
```

If `decord` or `av` fail:

* install separately, or
* comment them out and retry

---

### ✅ Verify Torch + CUDA

```bash
python -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.version.cuda)"
```

👉 `torch.cuda.is_available()` should be **True**

---

### Set Environment Variables

```bash
export VLM_MODEL_NAME="Qwen/Qwen3-VL-2B-Instruct" MAX_NEW_TOKENS=96 MAX_IMAGE_SIDE=768 SERIALIZE_VLM=1 OCR_GPU=0 YOLO_MODEL_PATH="best.pt" RETURN_TRACEBACK=1
```

---

### Start VLM Server

```bash
python app_server_VLM.py
```

---

## 🌐 3️⃣ Start ngrok (ONLY if using Vercel)

```bash
./ngrok http 5010
```

You will see:

```
Forwarding https://abc123.ngrok-free.dev -> http://localhost:5010
```

👉 Copy the HTTPS URL

👉 If you skip this step, go to Step 4 (Local Setup)

---

### 🔧 Update Vercel Environment Variable

Set:

```
OCR_PROXY_TARGET=https://abc123.ngrok-free.dev
```

Then redeploy your Vercel app

👉 Skip this if running locally

---

## 🌐 Vercel App

👉 Open:
[https://capstone-sp2026-low-vision.vercel.app/](https://capstone-sp2026-low-vision.vercel.app/)

---

## 💻 4️⃣ Local Setup (Run Everything Locally)

```bash
flutter clean
flutter pub get
flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010
```

---

## 📱 Running on Different Devices

| Device             | Command                                                                        |
| ------------------ | ------------------------------------------------------------------------------ |
| Web (Chrome)       | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010` |
| Android emulator   | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5010`                  |
| Phone (same Wi-Fi) | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5010`            |

---

## ⚠️ Important Notes

* ngrok must stay running:

  ```bash
  ./ngrok http 5010
  ```
* If ngrok stops → deployed app breaks
* Free ngrok URLs change each restart → update Vercel

---

## ✨ Features

* Supabase authentication
* Grocery lists
* Voice interaction (TTS/STT)
* Aisle scanning (OCR)
* Shelf scanning (YOLO + VLM)
* Accessible UI

---

## 📚 Resources

* [https://docs.flutter.dev/](https://docs.flutter.dev/)
* [https://supabase.com/docs](https://supabase.com/docs)
* [https://github.com/JaidedAI/EasyOCR](https://github.com/JaidedAI/EasyOCR)
