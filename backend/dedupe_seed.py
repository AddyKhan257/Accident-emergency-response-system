"""Removes duplicate seed rows (seed.py was run twice).

Keeps the oldest row of each duplicate group, points accidents and
notifications at it, then deletes the extra rows.  Safe to run again.

Run from WSL, project root:
    docker compose exec -T backend python - < backend/dedupe_seed.py
"""
import os

import pymysql

conn = pymysql.connect(
    host=os.getenv("DB_HOST", "db"),
    user=os.getenv("DB_USER", "root"),
    password=os.getenv("DB_PASSWORD", ""),
    database=os.getenv("DB_NAME", "aers"),
    port=int(os.getenv("DB_PORT", "3306")),
    autocommit=True,
)
cur = conn.cursor()


def dedupe(table, key_cols, repoint_sqls):
    same = " AND ".join(f"k.{c} <=> t.{c}" for c in key_cols)
    cur.execute(
        f"SELECT t.id, MIN(k.id) FROM {table} t JOIN {table} k ON {same} "
        f"GROUP BY t.id HAVING MIN(k.id) < t.id"
    )
    pairs = cur.fetchall()
    for dup, keep in pairs:
        for sql in repoint_sqls:
            cur.execute(sql, (keep, dup))
        cur.execute(f"DELETE FROM {table} WHERE id=%s", (dup,))
    cur.execute(f"SELECT COUNT(*) FROM {table}")
    print(f"{table}: removed {len(pairs)} duplicate(s), {cur.fetchone()[0]} left")


dedupe(
    "hospitals",
    ["name", "phone"],
    [
        "UPDATE accidents SET hospital_id=%s WHERE hospital_id=%s",
        "UPDATE notifications SET target_id=%s WHERE target_type='hospital' AND target_id=%s",
    ],
)
dedupe(
    "police_stations",
    ["name", "phone"],
    [
        "UPDATE accidents SET police_id=%s WHERE police_id=%s",
        "UPDATE notifications SET target_id=%s WHERE target_type='police' AND target_id=%s",
    ],
)
dedupe(
    "ambulances",
    ["vehicle_no"],
    ["UPDATE accidents SET ambulance_id=%s WHERE ambulance_id=%s"],
)
dedupe("donors", ["name", "phone"], [])
conn.close()
