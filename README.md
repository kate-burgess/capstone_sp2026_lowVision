# my_low_vision_app

A Flutter app that uses the camera to take a photo, saves the image to your computer (web: Downloads folder), and extracts text using EasyOCR via a local Python server.

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) installed
- Python 3 with: `pip install easyocr flask pillow numpy`
- For **Chrome (web)**: run the app with `flutter run -d chrome`
- For **Android**: device or emulator

## How to Run the Program

### 1. Start the OCR server (Python)

The app sends images to a local EasyOCR server. Start it first and leave it running:

```bash
cd C:\Users\alici\capstone\capstone_sp2026_lowVision
python ocr_server.py
```

You should see the server running on `http://0.0.0.0:5000`.

### 2. Run the Flutter app

Open a **second** terminal in the project folder:

```bash
cd C:\Users\alici\capstone\capstone_sp2026_lowVision
flutter pub get
flutter run -d chrome
```

- **Chrome (web):** `flutter run -d chrome` — use “Take photo” to use the camera, save the image to Downloads, and see extracted text.
- **Android (emulator or device):** start your emulator, then run `flutter run` and select the device, or use `flutter run -d <device-id>`.

To see available devices:

```bash
flutter devices
```

### Quick checklist

| Step | Command |
|------|--------|
| 1. Install Flutter deps | `flutter pub get` |
| 2. Start OCR server | `python ocr_server.py` |
| 3. Run app in Chrome | `flutter run -d chrome` |

---

## Project resources

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
- [Flutter documentation](https://docs.flutter.dev/)
