import io
from typing import List

import easyocr
import numpy as np
from flask import Flask, jsonify, request
from PIL import Image

app = Flask(__name__)

# Load EasyOCR reader once at startup.
reader = easyocr.Reader(["en"], gpu=False)


@app.post("/extract-text")
def extract_text():
    if "image" not in request.files:
        return jsonify({"error": "No image file provided"}), 400

    file_storage = request.files["image"]
    image_bytes = file_storage.read()

    try:
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except Exception:
        return jsonify({"error": "Could not read image"}), 400

    image_np = np.array(image)

    # detail=0 returns only text strings in a list
    results: List[str] = reader.readtext(image_np, detail=0)
    full_text = "\n".join(results).strip()

    if not full_text:
        full_text = "No text found"

    return jsonify(
        {
            "full_text": full_text,
            "lines": results,
        }
    )


if __name__ == "__main__":
    # Runs on port 5000 to match the Flutter app configuration.
    app.run(host="0.0.0.0", port=5000, debug=True)

import io
from typing import List

import easyocr
import numpy as np
from flask import Flask, jsonify, request
from PIL import Image

app = Flask(__name__)

# Load EasyOCR reader once at startup.
reader = easyocr.Reader(["en"], gpu=False)


@app.post("/extract-text")
def extract_text():
    if "image" not in request.files:
        return jsonify({"error": "No image file provided"}), 400

    file_storage = request.files["image"]
    image_bytes = file_storage.read()

    try:
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except Exception:
        return jsonify({"error": "Could not read image"}), 400

    image_np = np.array(image)

    # detail=0 returns only text strings in a list
    results: List[str] = reader.readtext(image_np, detail=0)
    full_text = "\n".join(results).strip()

    if not full_text:
        full_text = "No text found"

    return jsonify(
        {
            "full_text": full_text,
            "lines": results,
        }
    )


if __name__ == "__main__":
    # Runs on port 5000 to match the Flutter app configuration.
    app.run(host="0.0.0.0", port=5000, debug=True)

