````markdown
# my_low_vision_app

A Flutter app for low-vision users that combines Supabase-backed grocery list management, guided aisle/shelf scanning, VLM + OCR support, and voice-guided interaction.

---

## 🚀 How to Run (Simple)

### 1. Start Flask backend (profiles / lists)

```bash
cd backend2
python app.py
````

---

### 2. Set up and start VLM server (MAGIC)

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

Before installing PyTorch, verify your CUDA version:

```bash
nvidia-smi
```

Look for output like:

```
CUDA Version: 12.8
```

👉 You will use this to pick the correct PyTorch install (e.g., `cu128`).

---

### Install PyTorch (GPU)

⚠️ PyTorch must match your CUDA version.

Find the correct command here:
👉 [https://pytorch.org/get-started/locally/](https://pytorch.org/get-started/locally/)

**Example (CUDA 12.8):**

```bash
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
```

If needed, replace `cu128` (e.g., `cu121`).

---

### (Optional) Install Flash Attention (before requirements)

Try first:

```bash
pip install flash-attn --no-build-isolation
```

If that fails, install a matching prebuilt wheel.

Example (CUDA 12.8 + PyTorch 2.8.0):

```bash
pip install https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.7.16/flash_attn-2.8.3%2Bcu128torch2.8-cp310-cp310-linux_x86_64.whl
```

⚠️ Must match:

* CUDA (`cu128`)
* PyTorch (`torch2.8`)
* Python (`cp310`)

If it still fails → skip it.

---

### Install remaining requirements

```bash
pip install -r requirements.txt
```

If `decord` or `av` fail:

* install separately, or
* comment them out and retry

---

### Verify Torch + CUDA

```bash
python -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.version.cuda)"
```

✅ Expected:

* `torch.cuda.is_available()` → `True`

---

### Set environment variables

```bash
export VLM_MODEL_NAME="Qwen/Qwen3-VL-2B-Instruct"
export MAX_NEW_TOKENS=96
export MAX_IMAGE_SIDE=768
export SERIALIZE_VLM=1
export OCR_GPU=1
export YOLO_MODEL_PATH="best.pt"
export RETURN_TRACEBACK=1
```

---

### Start VLM server

```bash
python app_server_VLM.py
```

---

### 3. Run Flutter app (from root folder)

```bash
flutter clean
flutter pub get
flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010
```

---

## 📱 Running on Different Devices

| Where you run the app       | Command                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| Web (Chrome)                | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010` |
| Android emulator            | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5010`                  |
| Physical phone (same Wi-Fi) | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5010`            |

👉 Override anytime:

```bash
--dart-define=OCR_BASE_URL=http://your-server-ip:5010
```

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
* Aisle scanner (OCR + VLM)
* Shelf scanner (YOLO or VLM)
* Fully accessible UX with audio guidance

---

## 🔌 Server Ports

| Service            | Port |
| ------------------ | ---- |
| Flask backend      | 5000 |
| VLM server (MAGIC) | 5010 |

---

## 📚 Project Resources

* [https://docs.flutter.dev/](https://docs.flutter.dev/)
* [https://supabase.com/docs](https://supabase.com/docs)
* [https://github.com/JaidedAI/EasyOCR](https://github.com/JaidedAI/EasyOCR)

---

## ✅ Quick Checklist

### Backend

* [ ] `cd backend2`
* [ ] `python app.py`

### VLM Server

* [ ] `cd "VLM Testing"`
* [ ] `conda activate magic-vlm`
* [ ] check CUDA (`nvidia-smi`)
* [ ] install torch (correct CUDA)
* [ ] (optional) flash-attn
* [ ] `pip install -r requirements.txt`
* [ ] verify CUDA works
* [ ] set env variables
* [ ] `python app_server_VLM.py`

### Frontend

* [ ] `flutter clean`
* [ ] `flutter pub get`
* [ ] run with correct `OCR_BASE_URL`

```

This is already 🔥 for demos though.
```
