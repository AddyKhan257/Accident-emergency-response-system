import os
from datetime import timedelta

import pymysql
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_jwt_extended import (JWTManager, create_access_token, get_jwt,
                                get_jwt_identity, jwt_required)
from werkzeug.security import check_password_hash, generate_password_hash

load_dotenv()
app = Flask(__name__)
CORS(app)
app.config["JWT_SECRET_KEY"] = os.getenv("JWT_SECRET", "change-me")
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(days=7)
JWTManager(app)


# ---------- DB helpers ----------
def _conn():
    return pymysql.connect(
        host=os.getenv("DB_HOST", "localhost"),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "aers"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


def query(sql, args=(), one=False):
    conn = _conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            rows = cur.fetchall()
            if one:
                return rows[0] if rows else None
            return rows
    finally:
        conn.close()


def execute(sql, args=()):
    conn = _conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.lastrowid
    finally:
        conn.close()


def nearest(table, lat, lng):
    """Nearest hospital / police station using the haversine formula (km)."""
    sql = f"""
      SELECT *, (6371 * ACOS(LEAST(1,
        COS(RADIANS(%s)) * COS(RADIANS(lat)) * COS(RADIANS(lng) - RADIANS(%s))
        + SIN(RADIANS(%s)) * SIN(RADIANS(lat))))) AS distance_km
      FROM {table} ORDER BY distance_km LIMIT 1"""
    return query(sql, (lat, lng, lat), one=True)


def admin_only():
    return get_jwt().get("role") == "admin"


# ---------- Auth ----------
@app.post("/api/register")
def register():
    d = request.get_json() or {}
    for f in ("name", "email", "password"):
        if not d.get(f):
            return jsonify(error=f"{f} is required"), 400
    if query("SELECT id FROM users WHERE email=%s", (d["email"],), one=True):
        return jsonify(error="Email already registered"), 409
    uid = execute(
        "INSERT INTO users (name,email,phone,password_hash,blood_group) VALUES (%s,%s,%s,%s,%s)",
        (d["name"], d["email"], d.get("phone"),
         generate_password_hash(d["password"]), d.get("blood_group")),
    )
    return jsonify(message="Registered", user_id=uid), 201


@app.post("/api/login")
def login():
    d = request.get_json() or {}
    user = query("SELECT * FROM users WHERE email=%s", (d.get("email"),), one=True)
    if not user or not check_password_hash(user["password_hash"], d.get("password", "")):
        return jsonify(error="Invalid email or password"), 401
    token = create_access_token(identity=str(user["id"]),
                                additional_claims={"role": user["role"]})
    return jsonify(token=token, role=user["role"],
                   user={"id": user["id"], "name": user["name"], "email": user["email"]})


@app.get("/api/me")
@jwt_required()
def me():
    u = query("SELECT id,name,email,phone,blood_group,role FROM users WHERE id=%s",
              (get_jwt_identity(),), one=True)
    return jsonify(u)


@app.post("/api/fcm-token")
@jwt_required()
def save_fcm_token():
    execute("UPDATE users SET fcm_token=%s WHERE id=%s",
            ((request.get_json() or {}).get("token"), get_jwt_identity()))
    return jsonify(message="saved")


# ---------- Emergency contacts ----------
@app.get("/api/contacts")
@jwt_required()
def list_contacts():
    return jsonify(query("SELECT * FROM emergency_contacts WHERE user_id=%s",
                         (get_jwt_identity(),)))


@app.post("/api/contacts")
@jwt_required()
def add_contact():
    d = request.get_json() or {}
    if not d.get("name") or not d.get("phone"):
        return jsonify(error="name and phone required"), 400
    cid = execute(
        "INSERT INTO emergency_contacts (user_id,name,phone,relation) VALUES (%s,%s,%s,%s)",
        (get_jwt_identity(), d["name"], d["phone"], d.get("relation")))
    return jsonify(id=cid), 201


@app.delete("/api/contacts/<int:cid>")
@jwt_required()
def delete_contact(cid):
    execute("DELETE FROM emergency_contacts WHERE id=%s AND user_id=%s",
            (cid, get_jwt_identity()))
    return jsonify(message="deleted")


# ---------- SOS + accidents ----------
def create_accident(user_id, source, lat, lng, extra=None):
    extra = extra or {}
    hospital = nearest("hospitals", lat, lng)
    police = nearest("police_stations", lat, lng)
    aid = execute(
        """INSERT INTO accidents
           (user_id,source,accident_type,vehicle_no,people_count,description,lat,lng,hospital_id,police_id)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        (user_id, source, extra.get("accident_type"), extra.get("vehicle_no"),
         extra.get("people_count", 1), extra.get("description"), lat, lng,
         hospital["id"] if hospital else None, police["id"] if police else None))

    # simulated notifications (real FCM is added in a later step)
    if hospital:
        execute("INSERT INTO notifications (accident_id,target_type,target_id) VALUES (%s,'hospital',%s)",
                (aid, hospital["id"]))
    if police:
        execute("INSERT INTO notifications (accident_id,target_type,target_id) VALUES (%s,'police',%s)",
                (aid, police["id"]))
    contacts = query("SELECT id,name,phone,relation FROM emergency_contacts WHERE user_id=%s", (user_id,))
    for c in contacts:
        execute("INSERT INTO notifications (accident_id,target_type,target_id) VALUES (%s,'family',%s)",
                (aid, c["id"]))
    return aid, hospital, police, contacts


@app.post("/api/sos")
@jwt_required()
def sos():
    d = request.get_json() or {}
    if d.get("lat") is None or d.get("lng") is None:
        return jsonify(error="lat and lng required"), 400
    aid, hospital, police, contacts = create_accident(
        int(get_jwt_identity()), d.get("source", "sos"), d["lat"], d["lng"])
    return jsonify(accident_id=aid, status="pending",
                   hospital=hospital, police=police, family_notified=contacts), 201


@app.post("/api/accidents")
@jwt_required()
def report_accident():
    d = request.get_json() or {}
    if d.get("lat") is None or d.get("lng") is None:
        return jsonify(error="lat and lng required"), 400
    aid, hospital, police, contacts = create_accident(
        int(get_jwt_identity()), "report", d["lat"], d["lng"], d)
    return jsonify(accident_id=aid, hospital=hospital, police=police), 201


@app.get("/api/accidents")
@jwt_required()
def list_accidents():
    base = """SELECT a.*, h.name AS hospital_name, p.name AS police_name, u.name AS user_name
              FROM accidents a
              LEFT JOIN hospitals h ON h.id=a.hospital_id
              LEFT JOIN police_stations p ON p.id=a.police_id
              LEFT JOIN users u ON u.id=a.user_id """
    if admin_only():
        rows = query(base + "ORDER BY a.created_at DESC")
    else:
        rows = query(base + "WHERE a.user_id=%s ORDER BY a.created_at DESC",
                     (get_jwt_identity(),))
    return jsonify(rows)


@app.get("/api/hospitals/nearby")
@jwt_required()
def hospitals_nearby():
    lat, lng = request.args.get("lat", type=float), request.args.get("lng", type=float)
    if lat is None or lng is None:
        return jsonify(error="lat and lng required"), 400
    sql = """SELECT *, (6371 * ACOS(LEAST(1, COS(RADIANS(%s))*COS(RADIANS(lat))*COS(RADIANS(lng)-RADIANS(%s))
             + SIN(RADIANS(%s))*SIN(RADIANS(lat))))) AS distance_km
             FROM hospitals ORDER BY distance_km LIMIT 10"""
    return jsonify(query(sql, (lat, lng, lat)))


@app.get("/api/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)