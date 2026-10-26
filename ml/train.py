"""Train the accident-severity model.
Run from the project root (see instructions). Saves backend/model/severity_model.joblib
NOTE: uses synthetic data. Replace make_data() with a real dataset (e.g. Kaggle road accidents) later."""
import os
import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import train_test_split

VEHICLES = ["Bike", "Car", "Bus", "Truck", "Other"]
LABELS = ["Minor", "Moderate", "Severe"]
VEHICLE_RISK = {"Bike": 1.0, "Car": 0.2, "Bus": 0.6, "Truck": 0.8, "Other": 0.3}

rng = np.random.default_rng(42)


def make_data(n=6000):
    X, y = [], []
    for _ in range(n):
        v = rng.choice(VEHICLES)
        people = int(rng.integers(1, 7))
        speed = float(np.clip(rng.normal(55, 25), 5, 140))      # km/h before impact
        impact = float(np.clip(rng.normal(3.5, 2.0), 0.3, 12))  # accelerometer peak, in g
        hour = int(rng.integers(0, 24))
        night = 1.0 if (hour >= 22 or hour <= 5) else 0.0
        score = (0.035 * speed + 0.45 * impact + 0.25 * people
                 + VEHICLE_RISK[v] + 0.5 * night + rng.normal(0, 0.5))
        label = 0 if score < 3.6 else (1 if score < 5.2 else 2)
        X.append([VEHICLES.index(v), people, speed, impact, hour])
        y.append(label)
    return np.array(X, dtype=float), np.array(y)


if __name__ == "__main__":
    X, y = make_data()
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=1, stratify=y)
    model = RandomForestClassifier(n_estimators=150, max_depth=10, random_state=1)
    model.fit(Xtr, ytr)
    pred = model.predict(Xte)
    print("Accuracy:", round(accuracy_score(yte, pred), 3))
    print(classification_report(yte, pred, target_names=LABELS))

    out_dir = os.path.join("backend", "model")
    os.makedirs(out_dir, exist_ok=True)
    joblib.dump({"model": model, "vehicles": VEHICLES, "labels": LABELS},
                os.path.join(out_dir, "severity_model.joblib"))
    print("Saved to", out_dir)