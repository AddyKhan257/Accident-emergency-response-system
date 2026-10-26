import os, joblib, numpy as np
from flask import jsonify, request
from flask_jwt_extended import jwt_required


def register(app, execute):
    path = os.path.join(os.path.dirname(__file__), "model", "severity_model.joblib")
    bundle = joblib.load(path) if os.path.exists(path) else None

    @app.post("/api/predict")
    @jwt_required()
    def predict():
        if bundle is None:
            return jsonify(error="Model not trained yet"), 503
        d = request.get_json() or {}
        v = d.get("vehicle_type", "Other")
        if v not in bundle["vehicles"]:
            v = "Other"
        f = np.array([[bundle["vehicles"].index(v),
                       int(d.get("people_count", 1)),
                       float(d.get("speed", 40)),
                       float(d.get("impact_g", 3)),
                       int(d.get("hour", 12))]], dtype=float)
        p = bundle["model"].predict_proba(f)[0]
        i = int(np.argmax(p))
        sev, conf = bundle["labels"][i], round(float(p[i]), 3)
        if d.get("accident_id"):
            execute("UPDATE accidents SET severity=%s, confidence=%s WHERE id=%s",
                    (sev, conf, d["accident_id"]))
        return jsonify(severity=sev, confidence=conf)