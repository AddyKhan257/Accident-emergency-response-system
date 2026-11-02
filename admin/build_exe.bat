@echo off
cd /d %~dp0
.venv\Scripts\python.exe -m pip install pyinstaller
.venv\Scripts\python.exe -m PyInstaller --noconfirm --windowed --name AERS-Admin main.py
echo.
echo Done: dist\AERS-Admin\AERS-Admin.exe
pause
