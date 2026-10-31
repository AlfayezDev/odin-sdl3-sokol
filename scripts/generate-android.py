#!/usr/bin/env python3
"""Generate the Gradle scaffold; SDL supplies the Java Activity, CMake the native build."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

root = Path(__file__).resolve().parent.parent
config = json.loads((root / "project/android.json").read_text())
app_id, label = config["application_id"], config["label"]
if not re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+", app_id):
    raise SystemExit("application_id must be a lowercase dotted Android package name")
if not isinstance(label, str) or not label.strip():
    raise SystemExit("label must be a nonempty string")

# SDL's generator clears its output, so run it in a disposable staging directory.
(root / "build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=root / "build") as staging:
    subprocess.run([
        sys.executable, str(root / "deps/SDL3-3.2.28/build-scripts/create-android-project.py"),
        app_id, str(root / "app/entry.h"), "--variant", "symlink", "--output", staging,
    ], check=True)
    shutil.copytree(Path(staging) / app_id, root / "android", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("jni"))
activity = app_id + "." + app_id.rsplit(".", 1)[1].capitalize() + "Activity"
java = root / "android/app/src/main/java" / Path(*activity.split(".")).with_suffix(".java")
text = java.read_text()
java.write_text(text[:text.rfind("}")] + (root / "app/native/Toast.java.inc").read_text() + "}\n")


for source in sorted((root / "project/android").rglob("*")):
    if source.is_file():
        target = root / "android" / source.relative_to(root / "project/android")
        target.parent.mkdir(parents=True, exist_ok=True)
        text = source.read_text().replace("@APPLICATION_ID@", app_id)
        text = text.replace("@ACTIVITY@", activity)
        text = text.replace("@APP_LABEL@", escape(label, {'"': "&quot;"}))
        target.write_text(text)

sdl = root / "deps/SDL3-3.2.28/android-project"
for name in ["gradlew", "gradle/wrapper/gradle-wrapper.jar"]:
    shutil.copyfile(sdl / name, root / "android" / name)
(root / "android/gradlew").chmod(0o755)
print("Generated android/ (open this directory in Android Studio)")
