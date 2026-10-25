"""Run once after creating the DB:  python seed.py
Creates an admin user + test hospitals, police, ambulances, donors (around Pune - edit coords for your city)."""
from werkzeug.security import generate_password_hash
from app import execute, query

if not query("SELECT id FROM users WHERE email='admin@aers.com'", one=True):
    execute("INSERT INTO users (name,email,password_hash,role) VALUES (%s,%s,%s,'admin')",
            ("Admin", "admin@aers.com", generate_password_hash("admin123")))

for n, ph, lat, lng in [
    ("City Hospital", "020-111111", 18.5204, 73.8567),
    ("Government Hospital", "020-222222", 18.5300, 73.8700),
    ("Ruby Hall Clinic", "020-333333", 18.5360, 73.8770),
    ("Sahyadri Hospital", "020-444444", 18.5080, 73.8300),
]:
    execute("INSERT INTO hospitals (name,phone,city,lat,lng) VALUES (%s,%s,'Pune',%s,%s)", (n, ph, lat, lng))

for n, ph, lat, lng in [
    ("Shivajinagar Police Station", "020-555555", 18.5310, 73.8470),
    ("Kothrud Police Station", "020-666666", 18.5074, 73.8077),
    ("Hadapsar Police Station", "020-777777", 18.5089, 73.9259),
]:
    execute("INSERT INTO police_stations (name,phone,city,lat,lng) VALUES (%s,%s,'Pune',%s,%s)", (n, ph, lat, lng))

for v, d, ph, lat, lng in [
    ("MH 12 AB 7890", "Suresh Kumar", "9876500001", 18.5250, 73.8500),
    ("MH 12 AB 4567", "Ajay Patil", "9876500002", 18.5100, 73.8400),
    ("MH 12 XX 7690", "Ramesh More", "9876500003", 18.5400, 73.8800),
]:
    execute("INSERT INTO ambulances (vehicle_no,driver_name,phone,lat,lng) VALUES (%s,%s,%s,%s,%s)", (v, d, ph, lat, lng))

for n, ph, bg, lat, lng in [
    ("Rohit Sharma", "9876511111", "A+", 18.5210, 73.8560),
    ("Pooja Patil", "9876522222", "A+", 18.5330, 73.8710),
    ("Amit Verma", "9876533333", "O+", 18.5150, 73.8450),
    ("Neha Singh", "9876544444", "B+", 18.5400, 73.8600),
]:
    execute("INSERT INTO donors (name,phone,blood_group,city,lat,lng) VALUES (%s,%s,%s,'Pune',%s,%s)", (n, ph, bg, lat, lng))

print("Seed done. Admin login: admin@aers.com / admin123")