"""AERS Admin - Windows desktop dashboard (PySide6).

Talks to the same Flask API as the mobile app (login with the admin account).
Run:   py -3.12 main.py
Build: pyinstaller --noconfirm --windowed --name AERS-Admin main.py
"""
import csv
import json
import os
import sys

import requests
from PySide6.QtCore import QRectF, Qt, QTimer, QUrl
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import (
    QAbstractItemView,
    QSizePolicy,
    QApplication,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QStackedWidget,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

try:  # the live map needs Qt WebEngine (included with the PySide6 pip package)
    from PySide6.QtWebEngineWidgets import QWebEngineView
except Exception:  # pragma: no cover
    QWebEngineView = None

BASE_URL = os.environ.get("AERS_URL", "http://localhost:5000")
REFRESH_MS = 5000  # polling interval (no websockets, as planned)

NAVY = "#0D1B3E"
RED = "#E53935"
SEV_COLORS = {
    "Severe": "#E53935",
    "Moderate": "#FB8C00",
    "Minor": "#43A047",
    "Unrated": "#9E9E9E",
    "Unknown": "#9E9E9E",
}


# ------------------------------------------------------------------ API client
class ApiError(Exception):
    pass


class Api:
    token = None
    name = ""

    @classmethod
    def call(cls, method, path, json_body=None, params=None):
        headers = {"Authorization": f"Bearer {cls.token}"} if cls.token else {}
        try:
            r = requests.request(
                method,
                BASE_URL + path,
                headers=headers,
                json=json_body,
                params=params,
                timeout=15,
            )
        except requests.RequestException:
            raise ApiError(f"Cannot reach the server at {BASE_URL}. Is Docker running?")
        try:
            data = r.json()
        except ValueError:
            data = None
        if r.status_code >= 400:
            msg = None
            if isinstance(data, dict):
                msg = data.get("error") or data.get("msg") or data.get("message")
            raise ApiError(msg or f"Server error {r.status_code}")
        return data

    @classmethod
    def get(cls, path, **params):
        return cls.call("GET", path, params=params or None)

    @classmethod
    def login(cls, email, password):
        d = cls.call("POST", "/api/login", {"email": email, "password": password})
        token = d.get("token") or d.get("access_token")
        user = d.get("user") if isinstance(d.get("user"), dict) else {}
        role = d.get("role") or user.get("role") or cls._jwt_claim(token, "role")
        if not token or role != "admin":
            raise ApiError("This account is not an admin.")
        cls.token = token
        cls.name = user.get("name") or d.get("name") or "Admin"

    @staticmethod
    def _jwt_claim(token, key):
        try:
            import base64

            part = token.split(".")[1]
            part += "=" * (-len(part) % 4)
            return json.loads(base64.urlsafe_b64decode(part)).get(key)
        except Exception:
            return None


# --------------------------------------------------------------------- helpers
def cell(text, color=None, bold=False):
    it = QTableWidgetItem("" if text is None else str(text))
    it.setFlags(it.flags() & ~Qt.ItemFlag.ItemIsEditable)
    if color:
        it.setForeground(QColor(color))
    if bold:
        f = it.font()
        f.setBold(True)
        it.setFont(f)
    return it


def make_table(headers):
    t = QTableWidget(0, len(headers))
    t.setHorizontalHeaderLabels(headers)
    t.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
    t.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
    t.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
    t.setAlternatingRowColors(True)
    t.verticalHeader().setVisible(False)
    t.horizontalHeader().setStretchLastSection(True)
    return t


def button(text, slot, kind=""):
    b = QPushButton(text)
    if kind:
        b.setProperty("kind", kind)
    b.clicked.connect(slot)
    return b


def sev_label(a):
    return a.get("severity") or "Unrated"


class Page(QWidget):
    """Base page: a title row, an error line and a refresh() hook."""

    auto = False  # refresh every REFRESH_MS while visible

    def __init__(self, title):
        super().__init__()
        self.lay = QVBoxLayout(self)
        self.lay.setContentsMargins(24, 20, 24, 16)
        self.top = QHBoxLayout()
        t = QLabel(title)
        t.setObjectName("title")
        self.top.addWidget(t)
        self.top.addStretch()
        self.msg = QLabel("")
        self.msg.setObjectName("err")
        self.lay.addLayout(self.top)
        self.lay.addWidget(self.msg)

    def refresh(self):
        pass

    def safe_refresh(self):
        try:
            self.refresh()
            self.msg.setText("")
        except ApiError as e:
            self.msg.setText(str(e))

    def warn(self, text):
        QMessageBox.warning(self, "AERS Admin", text)

    def run(self, fn):
        """Run an action, show API errors in a message box, then refresh."""
        try:
            fn()
        except ApiError as e:
            self.warn(str(e))
        self.safe_refresh()


# ---------------------------------------------------------------------- charts
class BarChart(QWidget):
    def __init__(self, color=NAVY):
        super().__init__()
        self.color = QColor(color)
        self.data = []  # [(label, value)]
        self.setMinimumHeight(230)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

    def set_data(self, data):
        self.data = list(data)
        self.update()

    def paintEvent(self, _e):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        left, right, top, bottom = 40, 12, 18, 30
        cw, ch = w - left - right, h - top - bottom
        top_v = max([v for _, v in self.data] + [1])
        ymax = max(4, ((top_v + 3) // 4) * 4)
        grid = QPen(QColor("#E0E0E0"))
        text = QColor("#555555")
        p.setFont(QFont("Segoe UI", 8))
        for i in range(5):
            y = top + ch - ch * i / 4
            p.setPen(grid)
            p.drawLine(left, int(y), w - right, int(y))
            p.setPen(text)
            p.drawText(0, int(y) - 8, left - 6, 16, Qt.AlignmentFlag.AlignRight, str(int(ymax * i / 4)))
        n = max(len(self.data), 1)
        slot = cw / n
        bw = slot * 0.55
        for i, (label, v) in enumerate(self.data):
            x = left + i * slot + (slot - bw) / 2
            bh = ch * v / ymax
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(self.color)
            p.drawRoundedRect(QRectF(x, top + ch - bh, bw, bh), 3, 3)
            p.setPen(text)
            p.drawText(QRectF(x - 10, top + ch - bh - 16, bw + 20, 14), Qt.AlignmentFlag.AlignCenter, str(v))
            p.drawText(QRectF(left + i * slot, h - bottom + 6, slot, 16), Qt.AlignmentFlag.AlignCenter, str(label)[-5:])
        p.end()


class DonutChart(QWidget):
    def __init__(self):
        super().__init__()
        self.data = []  # [(label, value, "#hex")]
        self.setMinimumHeight(230)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

    def set_data(self, data):
        self.data = list(data)
        self.update()

    def paintEvent(self, _e):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        total = sum(v for _, v, _ in self.data)
        side = min(h - 30, w * 0.4)
        pw = side * 0.22
        rect = QRectF(20 + pw / 2, (h - side) / 2 + pw / 2, side - pw, side - pw)
        if total == 0:
            p.setPen(QPen(QColor("#E0E0E0"), pw))
            p.drawArc(rect, 0, 360 * 16)
        else:
            start = 90 * 16
            for _label, v, col in self.data:
                span = -int(round(v / total * 360 * 16))
                p.setPen(QPen(QColor(col), pw, Qt.PenStyle.SolidLine, Qt.PenCapStyle.FlatCap))
                p.drawArc(rect, start, span)
                start += span
        p.setPen(QColor(NAVY))
        f = QFont("Segoe UI", 18)
        f.setBold(True)
        p.setFont(f)
        p.drawText(rect, Qt.AlignmentFlag.AlignCenter, str(total))
        p.setFont(QFont("Segoe UI", 10))
        x = 20 + side + 24
        y = (h - 26 * len(self.data)) / 2
        for label, v, col in self.data:
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QColor(col))
            p.drawRoundedRect(QRectF(x, y + 4, 14, 14), 3, 3)
            p.setPen(QColor("#333333"))
            p.drawText(QRectF(x + 22, y, 200, 22), Qt.AlignmentFlag.AlignVCenter, f"{label}: {v}")
            y += 26
        p.end()


class Card(QFrame):
    def __init__(self, title, color=NAVY):
        super().__init__()
        self.setObjectName("card")
        lay = QVBoxLayout(self)
        t = QLabel(title)
        t.setObjectName("cardTitle")
        self.value = QLabel("-")
        self.value.setStyleSheet(f"font-size: 30px; font-weight: bold; color: {color};")
        lay.addWidget(t)
        lay.addWidget(self.value)

    def set(self, v):
        self.value.setText(str(v))


# --------------------------------------------------------- accident table widget
class AccidentTable(QWidget):
    COLS = ["ID", "Time", "User", "Source", "Type", "Severity", "Conf.", "Status", "Hospital", "Police", "Ambulance"]

    def __init__(self):
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        self.table = make_table(self.COLS)
        self.rows = []
        lay.addWidget(self.table)
        h = self.table.horizontalHeader()
        h.setSectionResizeMode(QHeaderView_Interactive())
        for i, wd in enumerate([50, 150, 90, 60, 90, 85, 55, 85, 120, 150, 110]):
            self.table.setColumnWidth(i, wd)

    def selected_row(self):
        r = self.table.currentRow()
        return self.rows[r] if 0 <= r < len(self.rows) else None

    def load(self, rows):
        sel = self.selected_row()
        sel_id = sel["id"] if sel else None
        self.rows = list(rows)
        t = self.table
        t.setRowCount(len(self.rows))
        for r, a in enumerate(self.rows):
            conf = a.get("confidence")
            conf_txt = f"{float(conf) * 100:.0f}%" if conf is not None else ""
            typ = a.get("accident_type") or ("SOS" if a.get("source") == "sos" else "")
            sev = sev_label(a)
            vals = [
                a.get("id"), a.get("created_at"), a.get("user_name"), a.get("source"), typ,
                sev, conf_txt, a.get("status"), a.get("hospital_name"), a.get("police_name"),
                a.get("ambulance_no"),
            ]
            for c, v in enumerate(vals):
                if c == 5:
                    t.setItem(r, c, cell(v, SEV_COLORS.get(sev, "#333333"), True))
                else:
                    t.setItem(r, c, cell(v))
            if sel_id is not None and a.get("id") == sel_id:
                t.selectRow(r)


def QHeaderView_Interactive():
    from PySide6.QtWidgets import QHeaderView

    return QHeaderView.ResizeMode.Interactive


# ------------------------------------------------------------------------ pages
class LoginPage(QWidget):
    def __init__(self, on_ok):
        super().__init__()
        self.on_ok = on_ok
        outer = QVBoxLayout(self)
        outer.addStretch()
        card = QFrame()
        card.setObjectName("loginCard")
        card.setFixedWidth(380)
        lay = QVBoxLayout(card)
        lay.setContentsMargins(28, 28, 28, 28)
        title = QLabel("AERS Admin")
        title.setStyleSheet(f"font-size: 28px; font-weight: bold; color: {NAVY};")
        sub = QLabel("Accident Emergency Response System")
        sub.setStyleSheet("color: #666666;")
        self.email = QLineEdit("admin@aers.com")
        self.email.setPlaceholderText("Email")
        self.password = QLineEdit()
        self.password.setPlaceholderText("Password")
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.password.returnPressed.connect(self.submit)
        self.err = QLabel("")
        self.err.setObjectName("err")
        self.err.setWordWrap(True)
        btn = button("Login", self.submit, "primary")
        for w in (title, sub, self.email, self.password, self.err, btn):
            lay.addWidget(w)
            lay.addSpacing(6)
        row = QHBoxLayout()
        row.addStretch()
        row.addWidget(card)
        row.addStretch()
        outer.addLayout(row)
        outer.addStretch()

    def submit(self):
        try:
            Api.login(self.email.text().strip(), self.password.text())
        except ApiError as e:
            self.err.setText(str(e))
            return
        self.err.setText("")
        self.password.clear()
        self.on_ok()


class DashboardPage(Page):
    auto = True

    def __init__(self):
        super().__init__("Dashboard")
        grid = QGridLayout()
        self.cards = {
            "total": Card("Total accidents"),
            "pending": Card("Pending", "#FB8C00"),
            "progress": Card("In progress", "#1E88E5"),
            "resolved": Card("Resolved", "#43A047"),
            "users": Card("Users"),
            "amb": Card("Ambulances available"),
        }
        for i, c in enumerate(self.cards.values()):
            grid.addWidget(c, 0, i)
        self.lay.addLayout(grid)
        row = QHBoxLayout()
        box1 = self._box("Accidents - last 7 days")
        self.trend = BarChart()
        box1.layout().addWidget(self.trend)
        box2 = self._box("Severity")
        self.donut = DonutChart()
        box2.layout().addWidget(self.donut)
        row.addWidget(box1, 3)
        row.addWidget(box2, 2)
        self.lay.addLayout(row, 1)

    def _box(self, title):
        f = QFrame()
        f.setObjectName("card")
        lay = QVBoxLayout(f)
        t = QLabel(title)
        t.setObjectName("cardTitle")
        lay.addWidget(t)
        return f

    def refresh(self):
        s = Api.get("/api/admin/stats")
        self.cards["total"].set(s["total_accidents"])
        self.cards["pending"].set(s["status"]["pending"])
        self.cards["progress"].set(s["status"]["in_progress"])
        self.cards["resolved"].set(s["status"]["resolved"])
        self.cards["users"].set(s["users"])
        self.cards["amb"].set(f"{s['ambulances']['available']}/{s['ambulances']['total']}")
        self.trend.set_data([(d["date"], d["count"]) for d in s["trend"]])
        sev = s["severity"]
        self.donut.set_data([
            ("Minor", sev["Minor"], SEV_COLORS["Minor"]),
            ("Moderate", sev["Moderate"], SEV_COLORS["Moderate"]),
            ("Severe", sev["Severe"], SEV_COLORS["Severe"]),
            ("Unrated", sev["Unknown"], SEV_COLORS["Unrated"]),
        ])


class AccidentsPage(Page):
    auto = True

    def __init__(self):
        super().__init__("Accident Management")
        self.sev = QComboBox()
        self.sev.addItems(["All severities", "Severe", "Moderate", "Minor"])
        self.status = QComboBox()
        self.status.addItems(["All statuses", "pending", "in_progress", "resolved"])
        for c in (self.sev, self.status):
            c.currentIndexChanged.connect(self.safe_refresh)
            self.top.addWidget(c)
        self.top.addWidget(button("Mark in progress", lambda: self.set_status("in_progress")))
        self.top.addWidget(button("Mark resolved", lambda: self.set_status("resolved"), "primary"))
        self.top.addWidget(button("Assign ambulance", self.assign))
        self.top.addWidget(button("Refresh", self.safe_refresh))
        self.tbl = AccidentTable()
        self.lay.addWidget(self.tbl)

    def refresh(self):
        params = {}
        if self.sev.currentIndex() > 0:
            params["severity"] = self.sev.currentText()
        if self.status.currentIndex() > 0:
            params["status"] = self.status.currentText()
        self.tbl.load(Api.get("/api/admin/accidents", **params))

    def _selected(self):
        a = self.tbl.selected_row()
        if not a:
            self.warn("Select an accident row first.")
        return a

    def set_status(self, status):
        a = self._selected()
        if a:
            self.run(lambda: Api.call("PATCH", f"/api/accidents/{a['id']}/status", {"status": status}))

    def assign(self):
        a = self._selected()
        if a:
            self.run(lambda: Api.call("POST", f"/api/accidents/{a['id']}/assign-ambulance", {}))


class SeverityPage(Page):
    auto = True

    def __init__(self):
        super().__init__("Severity Monitoring")
        row = QHBoxLayout()
        self.cards = {
            "Severe": Card("Severe", SEV_COLORS["Severe"]),
            "Moderate": Card("Moderate", SEV_COLORS["Moderate"]),
            "Minor": Card("Minor", SEV_COLORS["Minor"]),
        }
        for c in self.cards.values():
            row.addWidget(c)
        self.lay.addLayout(row)
        self.pick = QComboBox()
        self.pick.addItems(["Severe", "Moderate", "Minor"])
        self.pick.currentIndexChanged.connect(self.safe_refresh)
        self.top.addWidget(QLabel("Show:"))
        self.top.addWidget(self.pick)
        self.tbl = AccidentTable()
        self.lay.addWidget(self.tbl)

    def refresh(self):
        s = Api.get("/api/admin/stats")
        for k, c in self.cards.items():
            c.set(s["severity"][k])
        self.tbl.load(Api.get("/api/admin/accidents", severity=self.pick.currentText()))


MAP_HTML = """<!DOCTYPE html><html><head><meta charset="utf-8"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#map{height:100%;margin:0;font-family:Segoe UI,Arial}
.legend{position:absolute;bottom:14px;left:14px;z-index:999;background:#fff;padding:8px 12px;
border-radius:8px;box-shadow:0 1px 5px rgba(0,0,0,.3);font-size:13px}
.legend i{display:inline-block;width:11px;height:11px;border-radius:50%;margin:0 5px 0 10px}
.legend i:first-child{margin-left:0}</style></head><body>
<div id="map"></div>
<div id="offline" style="display:none;position:absolute;top:40%;width:100%;text-align:center;z-index:999;color:#B71C1C;font-size:16px">
Map could not load. Check your internet connection (Leaflet + OpenStreetMap need internet).</div>
<div class="legend"><i style="background:#E53935"></i>Severe<i style="background:#FB8C00"></i>Moderate
<i style="background:#43A047"></i>Minor<i style="background:#9E9E9E"></i>Unrated/resolved
<i style="background:#2E7D32;border:2px solid #fff"></i>Hospital<i style="background:#1A237E"></i>Police
<i style="background:#FF6F00"></i>Ambulance</div>
<script>
if(typeof L==='undefined'){document.getElementById('offline').style.display='block';
 function update(d){} } else {
var map=L.map('map').setView([18.52,73.85],12);
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',
 {maxZoom:19,attribution:'&copy; OpenStreetMap contributors'}).addTo(map);
var layer=L.layerGroup().addTo(map), first=true;
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){
 return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function dot(lat,lng,color,r,html){
 L.circleMarker([lat,lng],{radius:r,color:'#fff',weight:2,fillColor:color,fillOpacity:0.9})
  .bindPopup(html).addTo(layer);}
function update(d){
 layer.clearLayers(); var pts=[];
 var sev={Severe:'#E53935',Moderate:'#FB8C00',Minor:'#43A047'};
 d.hospitals.forEach(function(h){pts.push([h.lat,h.lng]);
  dot(h.lat,h.lng,'#2E7D32',7,'<b>'+esc(h.name)+'</b><br>Hospital<br>'+esc(h.phone));});
 d.police.forEach(function(h){pts.push([h.lat,h.lng]);
  dot(h.lat,h.lng,'#1A237E',7,'<b>'+esc(h.name)+'</b><br>Police<br>'+esc(h.phone));});
 d.ambulances.forEach(function(a){pts.push([a.lat,a.lng]);
  dot(a.lat,a.lng,'#FF6F00',8,'<b>'+esc(a.vehicle_no)+'</b><br>Ambulance: '+esc(a.status)+
  '<br>'+esc(a.driver_name));});
 d.accidents.forEach(function(a){pts.push([a.lat,a.lng]);
  var open=a.status!=='resolved';
  dot(a.lat,a.lng,open?(sev[a.severity]||'#9E9E9E'):'#9E9E9E',open?11:6,
  '<b>Accident #'+a.id+'</b><br>'+esc(a.severity||'Unrated')+' | '+esc(a.status)+
  '<br>'+esc(a.accident_type||a.source)+'<br>'+esc(a.user_name)+'<br>'+esc(a.created_at));});
 if(first&&pts.length){map.fitBounds(pts,{padding:[40,40],maxZoom:14});first=false;}
}
}
</script></body></html>"""


class MapPage(Page):
    auto = True

    def __init__(self):
        super().__init__("Live Accident Map")
        self.ready = False
        self.pending = None
        if QWebEngineView is None:
            self.view = None
            self.lay.addWidget(QLabel("Qt WebEngine is missing. Run: pip install PySide6"))
            return
        self.view = QWebEngineView()
        self.view.loadFinished.connect(self._loaded)
        self.view.setHtml(MAP_HTML, QUrl("https://aers.local/"))
        self.lay.addWidget(self.view, 1)

    def _loaded(self, ok):
        self.ready = bool(ok)
        if self.ready and self.pending is not None:
            self._push(self.pending)

    def _push(self, data):
        self.view.page().runJavaScript(f"update({json.dumps(data)});")

    def refresh(self):
        if self.view is None:
            return
        data = {
            "accidents": Api.get("/api/admin/accidents"),
            "hospitals": Api.get("/api/hospitals"),
            "police": Api.get("/api/police"),
            "ambulances": Api.get("/api/ambulances"),
        }
        self.pending = data
        if self.ready:
            self._push(data)


# ------------------------------------------------------------ CRUD (admin data)
FIELDS = {
    "hospitals": [("name", "Name"), ("phone", "Phone"), ("city", "City"), ("lat", "Latitude"), ("lng", "Longitude")],
    "police": [("name", "Name"), ("phone", "Phone"), ("city", "City"), ("lat", "Latitude"), ("lng", "Longitude")],
    "ambulances": [
        ("vehicle_no", "Vehicle no"), ("driver_name", "Driver"), ("phone", "Phone"),
        ("lat", "Latitude"), ("lng", "Longitude"), ("status", "Status"),
    ],
}
LIST_PATH = {"hospitals": "/api/hospitals", "police": "/api/police", "ambulances": "/api/ambulances"}
CHOICES = {"ambulances": {"status": ["available", "on_route", "busy"]}}


class FormDialog(QDialog):
    def __init__(self, title, fields, values=None, choices=None, parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(360)
        form = QFormLayout()
        self.edits = {}
        for key, label in fields:
            val = "" if not values or values.get(key) is None else str(values.get(key))
            if choices and key in choices:
                w = QComboBox()
                w.addItems(choices[key])
                if val in choices[key]:
                    w.setCurrentText(val)
            else:
                w = QLineEdit(val)
            self.edits[key] = w
            form.addRow(label, w)
        bb = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        lay = QVBoxLayout(self)
        lay.addLayout(form)
        lay.addWidget(bb)

    def values(self):
        out = {}
        for k, w in self.edits.items():
            out[k] = w.currentText() if isinstance(w, QComboBox) else w.text().strip()
        return out


class CrudPage(Page):
    def __init__(self, kind, title):
        super().__init__(title)
        self.kind = kind
        self.fields = FIELDS[kind]
        self.rows = []
        self.top.addWidget(button("Add", self.add, "primary"))
        self.top.addWidget(button("Edit", self.edit))
        self.top.addWidget(button("Delete", self.delete))
        self.top.addWidget(button("Refresh", self.safe_refresh))
        self.table = make_table([label for _, label in self.fields])
        self.table.cellDoubleClicked.connect(lambda *_: self.edit())
        self.lay.addWidget(self.table)

    def refresh(self):
        self.rows = Api.get(LIST_PATH[self.kind])
        self.table.setRowCount(len(self.rows))
        for r, row in enumerate(self.rows):
            for c, (key, _label) in enumerate(self.fields):
                self.table.setItem(r, c, cell(row.get(key)))

    def _selected(self):
        r = self.table.currentRow()
        if 0 <= r < len(self.rows):
            return self.rows[r]
        self.warn("Select a row first.")
        return None

    def _collect(self, dlg):
        v = dlg.values()
        for k in ("lat", "lng"):
            if k in v:
                try:
                    v[k] = float(v[k])
                except ValueError:
                    self.warn(f"{k} must be a number.")
                    return None
        return v

    def add(self):
        dlg = FormDialog(f"Add ({self.kind})", self.fields, None, CHOICES.get(self.kind), self)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        v = self._collect(dlg)
        if v:
            self.run(lambda: Api.call("POST", f"/api/admin/{self.kind}", v))

    def edit(self):
        row = self._selected()
        if not row:
            return
        dlg = FormDialog(f"Edit ({self.kind})", self.fields, row, CHOICES.get(self.kind), self)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        v = self._collect(dlg)
        if v:
            self.run(lambda: Api.call("PUT", f"/api/admin/{self.kind}/{row['id']}", v))

    def delete(self):
        row = self._selected()
        if not row:
            return
        name = row.get("name") or row.get("vehicle_no")
        ok = QMessageBox.question(self, "Delete", f"Delete '{name}'?")
        if ok == QMessageBox.StandardButton.Yes:
            self.run(lambda: Api.call("DELETE", f"/api/admin/{self.kind}/{row['id']}"))


class HospitalsPage(Page):
    """Hospital Management (+ police stations on a second tab)."""

    def __init__(self):
        super().__init__("Hospital Management")
        self.tabs = QTabWidget()
        self.hosp = CrudPage("hospitals", "Hospitals")
        self.pol = CrudPage("police", "Police stations")
        self.tabs.addTab(self.hosp, "Hospitals")
        self.tabs.addTab(self.pol, "Police stations")
        self.tabs.currentChanged.connect(lambda *_: self.safe_refresh())
        self.lay.addWidget(self.tabs)

    def refresh(self):
        self.tabs.currentWidget().refresh()


class AmbulancesPage(CrudPage):
    auto = True

    def __init__(self):
        super().__init__("ambulances", "Ambulance Management")
        self.top.insertWidget(self.top.count() - 1, button("Reset all to available", self.reset))

    def reset(self):
        self.run(lambda: Api.call("POST", "/api/admin/reset-ambulances", {}))


class NotificationsPage(Page):
    auto = True

    def __init__(self):
        super().__init__("Police Notification")
        self.kind = QComboBox()
        self.kind.addItems(["police", "hospital", "family"])
        self.kind.currentIndexChanged.connect(self.safe_refresh)
        self.top.addWidget(QLabel("Alerts sent to:"))
        self.top.addWidget(self.kind)
        self.top.addWidget(button("Acknowledge", self.ack, "primary"))
        self.table = make_table(["ID", "Time", "To", "Accident", "Type", "Severity", "Status"])
        self.rows = []
        self.lay.addWidget(self.table)

    def refresh(self):
        sel = self.table.currentRow()
        self.rows = Api.get("/api/admin/notifications", target_type=self.kind.currentText())
        self.table.setRowCount(len(self.rows))
        for r, n in enumerate(self.rows):
            sev = n.get("severity") or "Unrated"
            vals = [n["id"], n.get("created_at"), n.get("target_name"), f"#{n['accident_id']}",
                    n.get("accident_type") or "SOS", sev, n.get("status")]
            for c, v in enumerate(vals):
                if c == 5:
                    self.table.setItem(r, c, cell(v, SEV_COLORS.get(sev), True))
                elif c == 6:
                    self.table.setItem(r, c, cell(v, "#43A047" if v == "acknowledged" else "#FB8C00", True))
                else:
                    self.table.setItem(r, c, cell(v))
        if 0 <= sel < len(self.rows):
            self.table.selectRow(sel)

    def ack(self):
        r = self.table.currentRow()
        if not (0 <= r < len(self.rows)):
            self.warn("Select a notification first.")
            return
        nid = self.rows[r]["id"]
        self.run(lambda: Api.call("POST", f"/api/notifications/{nid}/ack", {}))


class UsersPage(Page):
    def __init__(self):
        super().__init__("User Management")
        self.top.addWidget(button("Refresh", self.safe_refresh))
        self.table = make_table(["ID", "Name", "Email", "Phone", "Blood group", "Role", "Joined"])
        self.lay.addWidget(self.table)

    def refresh(self):
        rows = Api.get("/api/admin/users")
        self.table.setRowCount(len(rows))
        for r, u in enumerate(rows):
            vals = [u["id"], u.get("name"), u.get("email"), u.get("phone"),
                    u.get("blood_group"), u.get("role"), u.get("created_at")]
            for c, v in enumerate(vals):
                self.table.setItem(r, c, cell(v, RED if (c == 5 and v == "admin") else None, c == 5 and v == "admin"))


class ReportsPage(Page):
    def __init__(self):
        super().__init__("Reports & Analytics")
        self.top.addWidget(button("Export all accidents (CSV)", self.export, "primary"))
        self.top.addWidget(button("Refresh", self.safe_refresh))
        self.summary = QLabel("")
        self.summary.setObjectName("summary")
        self.lay.addWidget(self.summary)
        row = QHBoxLayout()
        b1 = QFrame()
        b1.setObjectName("card")
        l1 = QVBoxLayout(b1)
        l1.addWidget(self._t("Accidents per day (last 7 days)"))
        self.trend = BarChart("#1E88E5")
        l1.addWidget(self.trend)
        b2 = QFrame()
        b2.setObjectName("card")
        l2 = QVBoxLayout(b2)
        l2.addWidget(self._t("Severity distribution"))
        self.donut = DonutChart()
        l2.addWidget(self.donut)
        b3 = QFrame()
        b3.setObjectName("card")
        l3 = QVBoxLayout(b3)
        l3.addWidget(self._t("Status"))
        self.status = DonutChart()
        l3.addWidget(self.status)
        row.addWidget(b1, 3)
        row.addWidget(b2, 2)
        row.addWidget(b3, 2)
        self.lay.addLayout(row, 1)

    def _t(self, text):
        t = QLabel(text)
        t.setObjectName("cardTitle")
        return t

    def refresh(self):
        s = Api.get("/api/admin/stats")
        total = s["total_accidents"]
        done = s["status"]["resolved"]
        severe = s["severity"]["Severe"]
        rate = f"{done * 100 // total}%" if total else "-"
        share = f"{severe * 100 // total}%" if total else "-"
        self.summary.setText(
            f"Total accidents: {total}    |    Resolution rate: {rate}    |    Severe share: {share}    |    "
            f"Hospitals: {s['hospitals']}    Police stations: {s['police']}    Users: {s['users']}"
        )
        self.trend.set_data([(d["date"], d["count"]) for d in s["trend"]])
        sev = s["severity"]
        self.donut.set_data([(k, sev[k], SEV_COLORS[k]) for k in ("Minor", "Moderate", "Severe", "Unknown")])
        st = s["status"]
        self.status.set_data([
            ("Pending", st["pending"], "#FB8C00"),
            ("In progress", st["in_progress"], "#1E88E5"),
            ("Resolved", st["resolved"], "#43A047"),
        ])

    def export(self):
        try:
            rows = Api.get("/api/admin/accidents")
        except ApiError as e:
            self.warn(str(e))
            return
        path, _ = QFileDialog.getSaveFileName(self, "Save CSV", "accidents.csv", "CSV files (*.csv)")
        if not path:
            return
        cols = ["id", "created_at", "user_name", "user_phone", "source", "accident_type", "vehicle_no",
                "people_count", "severity", "confidence", "status", "lat", "lng", "hospital_name",
                "police_name", "ambulance_no", "description"]
        with open(path, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(cols)
            for a in rows:
                w.writerow([a.get(c, "") for c in cols])
        QMessageBox.information(self, "AERS Admin", f"Saved {len(rows)} rows to\n{path}")


class HistoryPage(Page):
    def __init__(self):
        super().__init__("Accident History")
        self.search = QLineEdit()
        self.search.setPlaceholderText("Search name, type, severity, hospital...")
        self.search.textChanged.connect(self.apply_filter)
        self.search.setMinimumWidth(320)
        self.top.addWidget(self.search)
        self.top.addWidget(button("Refresh", self.safe_refresh))
        self.tbl = AccidentTable()
        self.tbl.table.cellDoubleClicked.connect(lambda *_: self.details())
        self.lay.addWidget(self.tbl)
        self.all_rows = []

    def refresh(self):
        self.all_rows = Api.get("/api/admin/accidents")
        self.apply_filter()

    def apply_filter(self):
        q = self.search.text().strip().lower()
        if not q:
            self.tbl.load(self.all_rows)
            return
        self.tbl.load([a for a in self.all_rows if q in " ".join(str(v) for v in a.values()).lower()])

    def details(self):
        a = self.tbl.selected_row()
        if not a:
            return
        text = "\n".join(
            f"{k}: {v}" for k, v in [
                ("Accident", f"#{a['id']}  ({a.get('created_at')})"),
                ("User", f"{a.get('user_name')}  {a.get('user_phone') or ''}"),
                ("Source / type", f"{a.get('source')} / {a.get('accident_type') or '-'}"),
                ("Vehicle", a.get("vehicle_no") or "-"),
                ("People", a.get("people_count")),
                ("Severity", f"{sev_label(a)}  ({a.get('confidence')})"),
                ("Status", a.get("status")),
                ("Location", f"{a.get('lat')}, {a.get('lng')}"),
                ("Hospital", a.get("hospital_name")),
                ("Police", a.get("police_name")),
                ("Ambulance", a.get("ambulance_no") or "-"),
                ("Description", a.get("description") or "-"),
            ]
        )
        QMessageBox.information(self, f"Accident #{a['id']}", text)


# ------------------------------------------------------------------ main window
STYLE = f"""
QWidget {{ font-family: 'Segoe UI', Arial; font-size: 13px; color: #222222; }}
QMainWindow, QStackedWidget, #content {{ background: #F4F6FA; }}
#title {{ font-size: 22px; font-weight: bold; color: {NAVY}; }}
#err {{ color: #B71C1C; }}
#summary {{ color: #444444; padding: 6px 0 10px 0; }}
#sidebar {{ background: {NAVY}; }}
#sidebar QLabel {{ color: white; font-size: 18px; font-weight: bold; padding: 18px 16px 8px 16px; }}
#sidebar QListWidget {{ background: transparent; border: none; outline: none; }}
#sidebar QListWidget::item {{ color: #C9D1E6; padding: 11px 18px; }}
#sidebar QListWidget::item:selected {{ background: #1B2C5A; color: white; border-left: 4px solid {RED}; }}
#sidebar QPushButton {{ background: transparent; color: #C9D1E6; border: 1px solid #3A4A78; margin: 12px; padding: 8px; }}
#card, #loginCard {{ background: white; border: 1px solid #E3E7F0; border-radius: 12px; }}
#cardTitle {{ color: #666666; font-size: 12px; }}
QPushButton {{ background: white; border: 1px solid #C5CCDB; border-radius: 6px; padding: 7px 14px; }}
QPushButton:hover {{ background: #EEF1F8; }}
QPushButton[kind="primary"] {{ background: {RED}; color: white; border: none; }}
QPushButton[kind="primary"]:hover {{ background: #C62828; }}
QLineEdit, QComboBox {{ background: white; border: 1px solid #C5CCDB; border-radius: 6px; padding: 6px 8px; }}
QTableWidget {{ background: white; alternate-background-color: #F7F9FD; border: 1px solid #E3E7F0; gridline-color: #EDF0F6; }}
QHeaderView::section {{ background: #E9EDF5; border: none; padding: 7px; font-weight: bold; }}
QTabWidget::pane {{ border: none; }}
"""

PAGES = [
    ("Dashboard", DashboardPage),
    ("Accident Management", AccidentsPage),
    ("Severity Monitoring", SeverityPage),
    ("Live Accident Map", MapPage),
    ("Hospital Management", HospitalsPage),
    ("Police Notification", NotificationsPage),
    ("Ambulance Management", AmbulancesPage),
    ("User Management", UsersPage),
    ("Reports & Analytics", ReportsPage),
    ("Accident History", HistoryPage),
]


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("AERS Admin")
        self.resize(1360, 820)
        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)
        self.login = LoginPage(self.start_session)
        self.stack.addWidget(self.login)
        self.shell = None
        self.pages = []
        self.timer = QTimer(self)
        self.timer.setInterval(REFRESH_MS)
        self.timer.timeout.connect(self.tick)

    def start_session(self):
        shell = QWidget()
        h = QHBoxLayout(shell)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(0)
        side = QFrame()
        side.setObjectName("sidebar")
        side.setFixedWidth(230)
        sl = QVBoxLayout(side)
        sl.setContentsMargins(0, 0, 0, 0)
        sl.addWidget(QLabel("AERS Admin"))
        self.nav = QListWidget()
        sl.addWidget(self.nav, 1)
        sl.addWidget(button(f"Logout ({Api.name})", self.logout))
        content = QStackedWidget()
        content.setObjectName("content")
        self.pages = []
        for name, cls in PAGES:
            page = cls()
            self.pages.append(page)
            content.addWidget(page)
            self.nav.addItem(name)
        self.content = content
        self.nav.currentRowChanged.connect(self.show_page)
        h.addWidget(side)
        h.addWidget(content, 1)
        self.shell = shell
        self.stack.addWidget(shell)
        self.stack.setCurrentWidget(shell)
        self.nav.setCurrentRow(0)
        self.timer.start()

    def show_page(self, i):
        if 0 <= i < len(self.pages):
            self.content.setCurrentIndex(i)
            self.pages[i].safe_refresh()

    def tick(self):
        i = self.content.currentIndex() if self.shell else -1
        if 0 <= i < len(self.pages) and self.pages[i].auto:
            self.pages[i].safe_refresh()

    def logout(self):
        self.timer.stop()
        Api.token = None
        if self.shell is not None:
            self.stack.removeWidget(self.shell)
            self.shell.deleteLater()
            self.shell = None
        self.stack.setCurrentWidget(self.login)


def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLE)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
