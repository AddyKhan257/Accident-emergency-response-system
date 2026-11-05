# AERS - Setup on a new Windows laptop

Accident Emergency Response System: Flutter Android app + Flask/MySQL backend (Docker)
+ Windows admin app (PySide6).

You need: Windows 10/11, internet, an Android phone with a USB cable.
You do NOT need Flutter or Android Studio just to run the project.

Keep the project in a simple folder such as `C:\projects\project1`
(not inside OneDrive, no spaces in the path).

---------------------------------------------------------------------

## 1. Install the tools (one time)

1. **Git**: https://git-scm.com/download/win
2. **Docker Desktop**: https://www.docker.com/products/docker-desktop/
   - Choose "Use WSL 2" during install, restart the laptop when asked.
   - If it complains about WSL: open PowerShell as Administrator, run `wsl --install`, restart.
   - If it complains about virtualization: enable "Intel VT-x / AMD SVM" in the BIOS.
   - Open Docker Desktop once and wait until it says "Engine running".
3. **Python 3.12** (for the admin app): https://www.python.org/downloads/
   - Tick "Add python.exe to PATH" and keep the "py launcher" option.
4. **Android platform-tools (adb)**: https://developer.android.com/tools/releases/platform-tools
   - Unzip to `C:\platform-tools` and add that folder to PATH (Start > "Edit environment variables").

Check in a NEW PowerShell window:

    git --version
    docker --version
    py -3.12 --version
    adb version

## 2. Get the code

    cd C:\projects
    git clone https://github.com/AddyKhan257/Accident-emergency-response-system.git project1
    cd project1

## 3. Create the .env file (important)

    Copy-Item .env.example .env
    notepad .env

Change `DB_PASSWORD` and `JWT_SECRET` to your own text. Keep `DB_NAME=aers`.

## 4. Start the backend + database

Docker Desktop must be running. In PowerShell, in the project folder:

    docker compose up --build -d

The first run downloads images and builds (5 to 10 minutes). Then:

    docker compose ps
    curl.exe http://localhost:5000/api/health

You must see `{"status":"ok"}`. If not: `docker compose logs backend --tail 30`.

## 5. Load the demo data (run this ONCE only)

    docker compose exec backend python seed.py

This creates the admin account and test hospitals, police stations, ambulances and donors.

- Admin login: `admin@aers.com` / `admin123`
- If you ran seed.py twice by mistake (everything shows twice), fix it with:

      Get-Content backend\dedupe_seed.py | docker compose exec -T backend python -

## 6. Run the Windows admin app

    cd admin
    py -3.12 -m venv .venv
    .\.venv\Scripts\python.exe -m pip install -r requirements.txt
    .\.venv\Scripts\python.exe main.py

Log in with the admin account. (The map page needs internet.)
Optional .exe: run `build_exe.bat`; result is `dist\AERS-Admin\AERS-Admin.exe`.

## 7. Install the app on the phone

Get `aers.apk` from the repository's **Releases** page on GitHub (or from whoever shared it).
This APK talks to `localhost:5000`, which reaches the laptop through USB (adb reverse).

On the phone:
1. Settings > About phone > tap "Build number" 7 times.
2. Settings > Developer options > turn on **USB debugging**.
3. Connect USB, choose "File transfer", tap **Allow** on the "Allow USB debugging?" popup.

On the laptop:

    adb devices                      # your phone must show as "device"
    adb reverse tcp:5000 tcp:5000    # redo this every time you re-plug the cable
    adb install -r aers.apk

(Or copy the APK to the phone and tap it to install.)

Open the AERS app > Create account > Login. The phone must stay connected by USB
while you use the app.

## 8. Try the full flow

1. Phone: add an emergency contact (Emergency Contacts tile).
2. Phone: press SOS > Send alert (or Voice SOS: say "help"; or Crash Detection > Simulate a crash).
3. Admin app > Accident Management: the new row appears within 5 seconds.
4. Select it > "Assign ambulance"; on the phone open "Ambulance & Tracking".
5. Admin: "Mark resolved".

Before a demo: Admin app > Ambulance Management > "Reset all to available".

## Every time you start again

1. Open Docker Desktop (wait for "Engine running").
2. `docker compose up -d` in the project folder.
3. Phone on USB: `adb reverse tcp:5000 tcp:5000`
4. Start the admin app.

Stop everything: `docker compose down` (data is kept). Delete all data too: `docker compose down -v`.

## Problems

| Problem | Fix |
|---|---|
| `docker` not recognized / "cannot connect to the Docker daemon" | Open Docker Desktop and wait for "Engine running" |
| `.env` error or "variable is not set" | Step 3 was skipped: create `.env` from `.env.example` |
| `port is already allocated` (5000 or 3307) | Another program uses it. Stop it, or restart the laptop |
| App says "Cannot reach server" | Run `adb reverse tcp:5000 tcp:5000` again and check the health URL |
| `adb devices` is empty | Better cable, "File transfer" mode, re-allow USB debugging, `adb kill-server` |
| Everything shows twice | seed.py ran twice: use the dedupe command in step 5 |
| Admin login fails | Run seed.py (step 5) and use `admin@aers.com` / `admin123` |
| Admin app: "not an admin" | Log in with the admin account, not a normal user |
| `pip install` fails for PySide6 | Use Python 3.12 (`py -3.12`), not the newest Python |

## Honest notes (for the report / viva)

- Hospital, police and ambulance data is test data; ambulance movement is simulated.
- The ML severity model is trained on generated (synthetic) data (about 81% test accuracy).
- Family/hospital/police "notifications" are rows in the database, not real SMS or push messages.
- Crash detection and voice recognition work while the app is open; voice needs internet.

## Developer notes (optional)

Rebuild the APK (needs Flutter): `cd mobile\aers_app` then `flutter build apk --release`.
For a phone on Wi-Fi instead of USB: `flutter build apk --release --dart-define=API_URL=http://LAPTOP-IP:5000`
and allow port 5000 in Windows Firewall.
