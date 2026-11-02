@echo off
cd /d %~dp0
if not exist .venv\Scripts\python.exe (
  echo Pehle setup karo - README.txt dekho
  pause
  exit /b 1
)
.venv\Scripts\python.exe main.py
