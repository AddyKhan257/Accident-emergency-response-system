AERS ADMIN (Windows desktop app)
================================
Setup (sirf ek baar) - PowerShell, is admin folder ke andar:

  cd C:\projects\project1\admin
  py -3.12 -m venv .venv
  .\.venv\Scripts\python.exe -m pip install -r requirements.txt

Run:
  .\.venv\Scripts\python.exe main.py        (ya run_admin.bat double-click)

Pehle backend chalu hona chahiye (WSL: docker compose up -d). App http://localhost:5000 se baat karti hai.
Doosra server ho to:  $env:AERS_URL="http://SERVER-IP:5000"

Admin login: sirf role=admin wala account chalega. Apna account admin banane ke liye (WSL, project folder):
  docker compose exec db mysql -uroot -p<DB_PASSWORD> aers -e "UPDATE users SET role='admin' WHERE email='tumhara@email.com';"
Phir app mein wahi email/password se login karo.

EXE banana (demo ke liye):  build_exe.bat  ->  dist\AERS-Admin\AERS-Admin.exe

Live map ko internet chahiye (OpenStreetMap tiles). Baaki sab local hai.
Pages: Dashboard, Accident Management, Severity Monitoring, Live Accident Map, Hospital Management (+Police),
Police Notification, Ambulance Management, User Management, Reports & Analytics (CSV export), Accident History.
Data har 5 second mein auto-refresh hota hai.
