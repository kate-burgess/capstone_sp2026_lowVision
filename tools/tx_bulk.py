import os

SKIP = {"translated_text.dart", "app_language.dart"}
ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")


def main() -> None:
    for root, _, files in os.walk(ROOT):
        for fn in files:
            if not fn.endswith(".dart") or fn in SKIP:
                continue
            path = os.path.join(root, fn)
            with open(path, encoding="utf-8") as f:
                s = f.read()
            orig = s
            s = s.replace("const Text(", "const Tx(")
            if s == orig:
                continue
            imp = "import 'translated_text.dart';\n"
            if "import 'translated_text.dart';" not in s:
                lines = s.splitlines(keepends=True)
                i = 0
                while i < len(lines) and lines[i].startswith("import "):
                    i += 1
                lines.insert(i, imp)
                s = "".join(lines)
            with open(path, "w", encoding="utf-8") as f:
                f.write(s)
            print("updated", path)


if __name__ == "__main__":
    main()
