"""Package the archived app as an unsigned IPA and check its contents."""
from pathlib import Path
import plistlib
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / "build/GymPlanner.xcarchive/Products/Applications/GymPlanner.app"
if not app.is_dir():
    sys.exit("The archive does not contain GymPlanner.app. Read the archive log.")
info = plistlib.loads((app / "Info.plist").read_bytes())
executable = app / info["CFBundleExecutable"]
if not executable.is_file() or executable.stat().st_size < 50_000:
    sys.exit("The app executable is missing or empty.")
if not (app / "Assets.car").is_file():
    sys.exit("The asset catalog (app icon) is missing.")
page = app / "index.html"
if not page.is_file() or page.read_bytes() != (root / "App/Resources/index.html").read_bytes():
    sys.exit("The app's page is missing from the bundle or differs from App/Resources/index.html.")
families = info.get("UIDeviceFamily")
if sorted(families or []) != [1, 2]:
    sys.exit(f"The app must support iPhone and iPad, found device families {families}.")
out = root / "build/Download"
out.mkdir(parents=True, exist_ok=True)
name = "Gym-Planner.ipa"
with zipfile.ZipFile(out / name, "w", zipfile.ZIP_DEFLATED) as z:
    for file in sorted(app.rglob("*")):
        if file.is_file():
            z.write(file, Path("Payload/GymPlanner.app") / file.relative_to(app))
print(f"Created {name} (unsigned): {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), "
      f"min iOS {info.get('MinimumOSVersion')}, device families {families}, page {page.stat().st_size} bytes")
