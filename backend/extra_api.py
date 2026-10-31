"""Extra API for AERS: mobile screens + admin desktop app.

Hook it up in app.py (above the  if __name__ == '__main__':  line):

    import extra_api
    extra_api.register(app)

Needs the tables from schema.sql (users, emergency_contacts, hospitals,
police_stations, ambulances, accidents, notifications, donors).
"""
import math
import os
from datetime import date, datetime, timedelta
from decimal import Decimal

import pymysql
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

bp = Blueprint("extra", __name__)


def register(app):
    app.register_blueprint(bp)


# ---------------------------------------------------------------- helpers
def _conn():
    return pymysql.connect(
        host=os.getenv("DB_HOST", "db"),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "aers"),
        port=int(os.getenv("DB_PORT", "3306")),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        charset="utf8mb4",
    )


def _q(sql, args=(), one=False):
    conn = _conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            rows = cur.fetchall()
        if one:
            return rows[0] if rows else None
        return list(rows)
    finally:
        conn.close()


def _run(sql, args=()):
    conn = _conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.lastrowid
    finally:
        conn.close()


def _clean(v):
    if isinstance(v, list):
        return [_clean(x) for x in v]
    if isinstance(v, dict):
        return {k: _clean(x) for k, x in v.items()}
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, date):
        return v.isoformat()
    return v


def _out(data, code=200):
    return jsonify(_clean(data)), code


def _err(msg, code=400):
    return _out({"error": msg}, code)


def _hav(lat1, lng1, lat2, lng2):
    """Distance in km."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _me():
    try:
        uid = int(get_jwt_identity())
    except (TypeError, ValueError):
        return None
    return _q(
        "SELECT id,name,email,phone,blood_group,role,created_at "
        "FROM users WHERE id=%s",
        (uid,),
        one=True,
    )


def _need_admin():
    u = _me()
    if not u or u["role"] != "admin":
        return None, _err("Admin only", 403)
    return u, None


def _accident_for(aid):
    """Returns (user, accident, error_response). Owner or admin only."""
    u = _me()
    acc = _q("SELECT * FROM accidents WHERE id=%s", (aid,), one=True)
    if not u or not acc or (u["role"] != "admin" and acc["user_id"] != u["id"]):
        return None, None, _err("Accident not found", 404)
    return u, acc, None


# ---------------------------------------------------------------- profile
@bp.get("/api/profile")
@jwt_required()
def profile():
    u = _me()
    if not u:
        return _err("User not found", 404)
    return _out(u)


@bp.put("/api/me")
@jwt_required()
def update_me():
    u = _me()
    if not u:
        return _err("User not found", 404)
    d = request.get_json(silent=True) or {}
    sets, args = [], []
    if "name" in d:
        name = (d.get("name") or "").strip()
        if not name:
            return _err("Name cannot be empty")
        sets.append("name=%s")
        args.append(name)
    if "phone" in d:
        sets.append("phone=%s")
        args.append((d.get("phone") or "").strip() or None)
    if "blood_group" in d:
        sets.append("blood_group=%s")
        args.append((d.get("blood_group") or "").strip() or None)
    if sets:
        _run("UPDATE users SET " + ",".join(sets) + " WHERE id=%s", (*args, u["id"]))
    return _out(_me())


# --------------------------------------------------- accidents (user side)
_ACC_LIST_SQL = (
    "SELECT a.id, a.user_id, a.source, a.accident_type, a.vehicle_no, "
    "a.people_count, a.description, a.lat, a.lng, a.severity, a.confidence, "
    "a.status, a.ambulance_id, a.created_at, "
    "h.name AS hospital_name, p.name AS police_name "
    "FROM accidents a "
    "LEFT JOIN hospitals h ON h.id = a.hospital_id "
    "LEFT JOIN police_stations p ON p.id = a.police_id "
)


@bp.get("/api/my/accidents")
@jwt_required()
def my_accidents():
    u = _me()
    if not u:
        return _err("User not found", 404)
    rows = _q(_ACC_LIST_SQL + "WHERE a.user_id=%s ORDER BY a.id DESC LIMIT 100", (u["id"],))
    return _out(rows)


@bp.get("/api/accidents/<int:aid>")
@jwt_required()
def accident_detail(aid):
    u, acc, bad = _accident_for(aid)
    if bad:
        return bad
    row = _q(_ACC_LIST_SQL + "WHERE a.id=%s", (aid,), one=True)
    return _out(row)


@bp.post("/api/accidents/<int:aid>/notify-family")
@jwt_required()
def notify_family(aid):
    """Creates a 'family' notification row for every emergency contact of
    the accident's owner (skips contacts that were already notified)."""
    u, acc, bad = _accident_for(aid)
    if bad:
        return bad
    contacts = _q(
        "SELECT id,name,phone,relation FROM emergency_contacts WHERE user_id=%s ORDER BY id",
        (acc["user_id"],),
    )
    done = {
        r["target_id"]
        for r in _q(
            "SELECT target_id FROM notifications WHERE accident_id=%s AND target_type='family'",
            (aid,),
        )
    }
    for c in contacts:
        if c["id"] not in done:
            _run(
                "INSERT INTO notifications (accident_id,target_type,target_id,status) "
                "VALUES (%s,'family',%s,'sent')",
                (aid, c["id"]),
            )
    return _out({"accident_id": aid, "family_notified": contacts})


# ------------------------------------------------- hospitals / police / donors
def _with_distance(rows):
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    if lat is not None and lng is not None:
        for r in rows:
            if r.get("lat") is not None and r.get("lng") is not None:
                r["distance_km"] = round(_hav(lat, lng, float(r["lat"]), float(r["lng"])), 2)
        rows.sort(key=lambda r: r.get("distance_km", 1e9))
    return rows


@bp.get("/api/hospitals")
@jwt_required()
def hospitals():
    rows = _q("SELECT id,name,phone,city,lat,lng FROM hospitals ORDER BY id")
    return _out(_with_distance(rows))


@bp.get("/api/police")
@jwt_required()
def police():
    rows = _q("SELECT id,name,phone,city,lat,lng FROM police_stations ORDER BY id")
    return _out(_with_distance(rows))


@bp.get("/api/donors")
@jwt_required()
def donors():
    bg = (request.args.get("blood_group") or "").strip()
    if bg:
        rows = _q(
            "SELECT id,name,phone,blood_group,city,lat,lng FROM donors WHERE blood_group=%s",
            (bg,),
        )
    else:
        rows = _q("SELECT id,name,phone,blood_group,city,lat,lng FROM donors")
    return _out(_with_distance(rows))


# ------------------------------------------------- ambulance (simulated)
def _assign_ambulance(acc, ambulance_id=None):
    """Assign an ambulance to the accident. Returns (ambulance, error)."""
    if acc["ambulance_id"]:
        amb = _q("SELECT * FROM ambulances WHERE id=%s", (acc["ambulance_id"],), one=True)
        return amb, None
    if ambulance_id:
        amb = _q("SELECT * FROM ambulances WHERE id=%s", (ambulance_id,), one=True)
        if not amb:
            return None, "Ambulance not found"
    else:
        cands = _q("SELECT * FROM ambulances WHERE status='available'")
        if not cands:
            # demo friendly: reuse the nearest ambulance that is not on a run
            cands = _q("SELECT * FROM ambulances WHERE status<>'on_route'") or _q(
                "SELECT * FROM ambulances"
            )
        if not cands:
            return None, "No ambulance in the system (run seed.py)"
        alat, alng = float(acc["lat"]), float(acc["lng"])
        amb = min(cands, key=lambda a: _hav(alat, alng, float(a["lat"]), float(a["lng"])))
    _run("UPDATE ambulances SET status='on_route' WHERE id=%s", (amb["id"],))
    _run(
        "UPDATE accidents SET ambulance_id=%s, status='in_progress' WHERE id=%s",
        (amb["id"], acc["id"]),
    )
    amb["status"] = "on_route"
    return amb, None


@bp.post("/api/accidents/<int:aid>/dispatch")
@jwt_required()
def dispatch(aid):
    """Owner (or admin) asks for the nearest ambulance (simulated)."""
    u, acc, bad = _accident_for(aid)
    if bad:
        return bad
    amb, e = _assign_ambulance(acc)
    if e:
        return _err(e, 409)
    return _out({"accident_id": aid, "ambulance": amb})


@bp.post("/api/accidents/<int:aid>/assign-ambulance")
@jwt_required()
def assign_ambulance(aid):
    u, bad = _need_admin()
    if bad:
        return bad
    acc = _q("SELECT * FROM accidents WHERE id=%s", (aid,), one=True)
    if not acc:
        return _err("Accident not found", 404)
    d = request.get_json(silent=True) or {}
    amb, e = _assign_ambulance(acc, d.get("ambulance_id"))
    if e:
        return _err(e, 409)
    return _out({"accident_id": aid, "ambulance": amb})


@bp.get("/api/accidents/<int:aid>/track")
@jwt_required()
def track(aid):
    """Status + (simulated) ambulance position. Every call moves an
    on-route ambulance 35% closer to the accident."""
    u, acc, bad = _accident_for(aid)
    if bad:
        return bad
    alat, alng = float(acc["lat"]), float(acc["lng"])
    amb, dist, eta, arrived = None, None, None, False
    if acc["ambulance_id"]:
        amb = _q("SELECT * FROM ambulances WHERE id=%s", (acc["ambulance_id"],), one=True)
    if amb:
        lat, lng = float(amb["lat"]), float(amb["lng"])
        dist = _hav(lat, lng, alat, alng)
        if amb["status"] == "on_route":
            if dist <= 0.15:
                lat, lng, dist = alat, alng, 0.0
                _run(
                    "UPDATE ambulances SET lat=%s,lng=%s,status='busy' WHERE id=%s",
                    (lat, lng, amb["id"]),
                )
                amb["status"] = "busy"
            else:
                lat += (alat - lat) * 0.35
                lng += (alng - lng) * 0.35
                dist = _hav(lat, lng, alat, alng)
                _run("UPDATE ambulances SET lat=%s,lng=%s WHERE id=%s", (lat, lng, amb["id"]))
        amb["lat"], amb["lng"] = lat, lng
        arrived = dist <= 0.15
        eta = 0 if arrived else max(1, round(dist / 0.5))  # ~30 km/h
    hospital = (
        _q("SELECT id,name,phone,lat,lng FROM hospitals WHERE id=%s", (acc["hospital_id"],), one=True)
        if acc["hospital_id"]
        else None
    )
    police_row = (
        _q("SELECT id,name,phone,lat,lng FROM police_stations WHERE id=%s", (acc["police_id"],), one=True)
        if acc["police_id"]
        else None
    )
    return _out(
        {
            "accident": {
                "id": acc["id"],
                "lat": acc["lat"],
                "lng": acc["lng"],
                "severity": acc["severity"],
                "status": acc["status"],
                "accident_type": acc["accident_type"],
            },
            "hospital": hospital,
            "police": police_row,
            "ambulance": amb,
            "distance_km": None if dist is None else round(dist, 2),
            "eta_min": eta,
            "arrived": arrived,
        }
    )


# ----------------------------------------------------------- admin: accidents
@bp.get("/api/admin/accidents")
@jwt_required()
def admin_accidents():
    u, bad = _need_admin()
    if bad:
        return bad
    where, args = [], []
    for col in ("severity", "status"):
        v = request.args.get(col)
        if v:
            where.append(f"a.{col}=%s")
            args.append(v)
    sql = (
        "SELECT a.id, a.user_id, u.name AS user_name, u.phone AS user_phone, "
        "a.source, a.accident_type, a.vehicle_no, a.people_count, a.description, "
        "a.lat, a.lng, a.severity, a.confidence, a.status, a.ambulance_id, a.created_at, "
        "h.name AS hospital_name, p.name AS police_name, am.vehicle_no AS ambulance_no "
        "FROM accidents a "
        "LEFT JOIN users u ON u.id = a.user_id "
        "LEFT JOIN hospitals h ON h.id = a.hospital_id "
        "LEFT JOIN police_stations p ON p.id = a.police_id "
        "LEFT JOIN ambulances am ON am.id = a.ambulance_id "
    )
    if where:
        sql += "WHERE " + " AND ".join(where) + " "
    sql += "ORDER BY a.id DESC LIMIT 500"
    return _out(_q(sql, tuple(args)))


@bp.patch("/api/accidents/<int:aid>/status")
@jwt_required()
def set_status(aid):
    u, bad = _need_admin()
    if bad:
        return bad
    d = request.get_json(silent=True) or {}
    status = d.get("status")
    if status not in ("pending", "in_progress", "resolved"):
        return _err("status must be pending, in_progress or resolved")
    acc = _q("SELECT * FROM accidents WHERE id=%s", (aid,), one=True)
    if not acc:
        return _err("Accident not found", 404)
    _run("UPDATE accidents SET status=%s WHERE id=%s", (status, aid))
    if status == "resolved" and acc["ambulance_id"]:
        _run("UPDATE ambulances SET status='available' WHERE id=%s", (acc["ambulance_id"],))
    return _out({"id": aid, "status": status})


# ------------------------------------------------------ admin: notifications
@bp.get("/api/admin/notifications")
@jwt_required()
def admin_notifications():
    u, bad = _need_admin()
    if bad:
        return bad
    sql = (
        "SELECT n.id, n.accident_id, n.target_type, n.target_id, n.status, n.created_at, "
        "a.severity, a.accident_type, a.lat, a.lng, "
        "CASE n.target_type WHEN 'hospital' THEN h.name WHEN 'police' THEN p.name "
        "ELSE c.name END AS target_name "
        "FROM notifications n "
        "JOIN accidents a ON a.id = n.accident_id "
        "LEFT JOIN hospitals h ON n.target_type='hospital' AND h.id = n.target_id "
        "LEFT JOIN police_stations p ON n.target_type='police' AND p.id = n.target_id "
        "LEFT JOIN emergency_contacts c ON n.target_type='family' AND c.id = n.target_id "
    )
    args = ()
    tt = request.args.get("target_type")
    if tt:
        sql += "WHERE n.target_type=%s "
        args = (tt,)
    sql += "ORDER BY n.id DESC LIMIT 300"
    return _out(_q(sql, args))


@bp.post("/api/notifications/<int:nid>/ack")
@jwt_required()
def ack_notification(nid):
    u, bad = _need_admin()
    if bad:
        return bad
    _run("UPDATE notifications SET status='acknowledged' WHERE id=%s", (nid,))
    return _out({"id": nid, "status": "acknowledged"})


# ------------------------------------------------------------ admin: stats
@bp.get("/api/admin/stats")
@jwt_required()
def admin_stats():
    u, bad = _need_admin()
    if bad:
        return bad
    total = _q("SELECT COUNT(*) AS c FROM accidents", one=True)["c"]
    sev = {
        r["k"]: r["c"]
        for r in _q(
            "SELECT COALESCE(severity,'Unknown') AS k, COUNT(*) AS c FROM accidents GROUP BY k"
        )
    }
    st = {r["k"]: r["c"] for r in _q("SELECT status AS k, COUNT(*) AS c FROM accidents GROUP BY status")}
    today = date.today()
    counts = {
        r["d"]: r["c"]
        for r in _q(
            "SELECT DATE(created_at) AS d, COUNT(*) AS c FROM accidents "
            "WHERE created_at >= %s GROUP BY DATE(created_at)",
            (today - timedelta(days=6),),
        )
    }
    trend = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        trend.append({"date": day.isoformat(), "count": counts.get(day, 0)})
    amb = _q(
        "SELECT COUNT(*) AS total, SUM(status='available') AS available FROM ambulances",
        one=True,
    )
    return _out(
        {
            "total_accidents": total,
            "severity": {
                "Minor": sev.get("Minor", 0),
                "Moderate": sev.get("Moderate", 0),
                "Severe": sev.get("Severe", 0),
                "Unknown": sev.get("Unknown", 0),
            },
            "status": {
                "pending": st.get("pending", 0),
                "in_progress": st.get("in_progress", 0),
                "resolved": st.get("resolved", 0),
            },
            "users": _q("SELECT COUNT(*) AS c FROM users WHERE role='user'", one=True)["c"],
            "hospitals": _q("SELECT COUNT(*) AS c FROM hospitals", one=True)["c"],
            "police": _q("SELECT COUNT(*) AS c FROM police_stations", one=True)["c"],
            "ambulances": {
                "total": int(amb["total"] or 0),
                "available": int(amb["available"] or 0),
            },
            "trend": trend,
        }
    )


@bp.get("/api/admin/users")
@jwt_required()
def admin_users():
    u, bad = _need_admin()
    if bad:
        return bad
    return _out(
        _q("SELECT id,name,email,phone,blood_group,role,created_at FROM users ORDER BY id DESC")
    )


@bp.post("/api/admin/reset-ambulances")
@jwt_required()
def reset_ambulances():
    u, bad = _need_admin()
    if bad:
        return bad
    _run("UPDATE ambulances SET status='available'")
    return _out({"ok": True})


# --------------------------------------------- admin: hospitals/police/ambulances
_KINDS = {
    "hospitals": ("hospitals", ("name", "phone", "city", "lat", "lng")),
    "police": ("police_stations", ("name", "phone", "city", "lat", "lng")),
    "ambulances": ("ambulances", ("vehicle_no", "driver_name", "phone", "lat", "lng", "status")),
}


@bp.get("/api/ambulances")
@jwt_required()
def ambulances():
    u, bad = _need_admin()
    if bad:
        return bad
    return _out(_q("SELECT * FROM ambulances ORDER BY id"))


@bp.post("/api/admin/<kind>")
@jwt_required()
def admin_create(kind):
    u, bad = _need_admin()
    if bad:
        return bad
    if kind not in _KINDS:
        return _err("Unknown type", 404)
    table, cols = _KINDS[kind]
    d = request.get_json(silent=True) or {}
    if not str(d.get(cols[0]) or "").strip():
        return _err(f"{cols[0]} is required")
    use = [c for c in cols if c in d]
    new_id = _run(
        f"INSERT INTO {table} ({','.join(use)}) VALUES ({','.join(['%s'] * len(use))})",
        tuple(d[c] for c in use),
    )
    return _out(_q(f"SELECT * FROM {table} WHERE id=%s", (new_id,), one=True), 201)


@bp.put("/api/admin/<kind>/<int:rid>")
@jwt_required()
def admin_update(kind, rid):
    u, bad = _need_admin()
    if bad:
        return bad
    if kind not in _KINDS:
        return _err("Unknown type", 404)
    table, cols = _KINDS[kind]
    d = request.get_json(silent=True) or {}
    use = [c for c in cols if c in d]
    if not use:
        return _err("Nothing to update")
    _run(
        f"UPDATE {table} SET {','.join(c + '=%s' for c in use)} WHERE id=%s",
        (*[d[c] for c in use], rid),
    )
    row = _q(f"SELECT * FROM {table} WHERE id=%s", (rid,), one=True)
    if not row:
        return _err("Not found", 404)
    return _out(row)


@bp.delete("/api/admin/<kind>/<int:rid>")
@jwt_required()
def admin_delete(kind, rid):
    u, bad = _need_admin()
    if bad:
        return bad
    if kind not in _KINDS:
        return _err("Unknown type", 404)
    table, _cols = _KINDS[kind]
    try:
        _run(f"DELETE FROM {table} WHERE id=%s", (rid,))
    except pymysql.err.IntegrityError:
        return _err("Cannot delete: it is used by existing accidents", 409)
    return _out({"deleted": rid})
