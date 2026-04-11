#!/bin/bash

# ----------- 1. GUI-BASED ELEVATION -----------
if [ "$EUID" -ne 0 ]; then
    if command -v pkexec >/dev/null 2>&1; then
        pkexec env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" ORIG_UID="$UID" "$0" "$@"
        exit $?
    else
        echo "Error: pkexec not found. Please run with sudo."
        exit 1
    fi
fi

# ----------- 2. SYSTEM DETECTION -----------
detect_pm() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|linuxmint|pop) echo "apt" ;;
            fedora|rhel|centos|rocky|almalinux) echo "dnf" ;;
            opensuse*|sles) echo "zypper" ;;
            arch|manjaro|endeavouros) echo "pacman" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}
PM_TYPE=$(detect_pm)

# ----------- 3. GRANULAR DEPENDENCY CHECK -----------
ensure_pkg() {
    local label=$1; local check_cmd=$2; local apt_pkg=$3; local dnf_pkg=$4; local pacman_pkg=$5; local zyp_pkg=$6
    if ! eval "$check_cmd" &>/dev/null; then
        echo "🛠️  $label is missing. Installing..."
        case $PM_TYPE in
            apt) apt update && apt install -y $apt_pkg ;;
            dnf) dnf install -y $dnf_pkg ;;
            pacman) pacman -Sy --noconfirm $pacman_pkg ;;
            zypper) zypper install -y $zyp_pkg ;;
        esac
    else
        echo "✅ $label is already installed."
    fi
}

ensure_pkg "Python 3" "command -v python3" "python3" "python3" "python" "python3"
ensure_pkg "Tkinter" "python3 -c 'import tkinter'" "python3-tk" "python3-tkinter" "tk" "python3-tk"
ensure_pkg "Pillow" "python3 -c 'from PIL import Image, ImageTk'" \
           "python3-pil python3-pil.imagetk" "python3-pillow python3-pillow-tk" \
           "python-pillow" "python3-Pillow python3-Pillow-tk"

# ----------- 4. THE PYTHON ENGINE -----------
PY_FILE="/tmp/linux_sweep_engine.py"

cat << 'EOF' > "$PY_FILE"
import os, sys, json, subprocess, tkinter as tk
from tkinter import ttk, messagebox, filedialog
from PIL import Image, ImageTk
import threading, queue, pwd, signal

# Core system protections
PROTECTED = ["python3", "python", "pkexec", "tkinter", "niri", "snapd", "flatpak", "bash", "sudo"]
COLOR_BG, COLOR_HOVER, COLOR_SELECTED = "#ffffff", "#f8f9fa", "#e7f3ff"
COLOR_BORDER, COLOR_TEXT, COLOR_ACCENT = "#e0e0e0", "#333333", "#1976d2"
COLOR_IMPORT, COLOR_EXPORT, COLOR_DANGER = "#4caf50", "#607d8b", "#f44336"

def get_user_home():
    try:
        uid = os.environ.get('ORIG_UID') or os.environ.get('PKEXEC_UID') or os.environ.get('SUDO_UID')
        if uid: return pwd.getpwuid(int(uid)).pw_dir
    except: pass
    return os.path.expanduser('~')
USER_HOME = get_user_home()

class CustomConfirm(tk.Toplevel):
    def __init__(self, parent, count, callback):
        super().__init__(parent)
        self.title("Confirm Removal")
        self.geometry("450x280")
        self.configure(bg=COLOR_BG)
        self.resizable(False, False)
        self.transient(parent); self.grab_set()
        self.callback = callback
        f = tk.Frame(self, bg=COLOR_BG); f.pack(expand=True)
        tk.Label(f, text="⚠ Confirm Purge", font=("Arial", 14, "bold"), bg=COLOR_BG, fg=COLOR_DANGER).pack(pady=(0, 15))
        tk.Label(f, text=f"Uninstall {count} apps and all related components?", font=("Arial", 11), bg=COLOR_BG, fg=COLOR_TEXT).pack(pady=10)
        btn_f = tk.Frame(f, bg=COLOR_BG, pady=20); btn_f.pack()
        cfg = {"font": ("Arial", 10, "bold"), "relief": "flat", "fg": "white", "padx": 25, "pady": 8, "cursor": "hand2"}
        tk.Button(btn_f, text="CANCEL", bg=COLOR_EXPORT, command=self.destroy, **cfg).pack(side="left", padx=10)
        tk.Button(btn_f, text="UNINSTALL", bg=COLOR_DANGER, command=self.confirm, **cfg).pack(side="left", padx=10)
    def confirm(self): self.destroy(); self.callback()

class LogWindow(tk.Toplevel):
    def __init__(self, parent, cancel_callback):
        super().__init__(parent)
        self.title("LinuxSweep Logs")
        self.geometry("750x650")
        self.configure(bg=COLOR_BG)
        self.protocol("WM_DELETE_WINDOW", self.on_attempt_close)
        self.cancel_callback = cancel_callback
        self.finished = False

        self.label = tk.Label(self, text="Purging Applications...", font=("Arial", 12, "bold"), bg=COLOR_BG, fg=COLOR_TEXT, pady=20)
        self.label.pack()
        self.progress = ttk.Progressbar(self, mode='indeterminate', length=650)
        self.progress.pack(pady=5, padx=30); self.progress.start(15)

        self.log_container = tk.Frame(self, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER)
        self.log_container.pack(fill="both", expand=True, padx=30, pady=20)
        self.text_area = tk.Text(self.log_container, bg="#fafafa", fg=COLOR_TEXT, font=("Monospace", 9), relief="flat", padx=15, pady=15)
        self.scrollbar = ttk.Scrollbar(self.log_container, orient="vertical", command=self.text_area.yview)
        self.text_area.configure(yscrollcommand=self.scrollbar.set)
        self.text_area.pack(side="left", fill="both", expand=True); self.scrollbar.pack(side="right", fill="y")

        # Independent Scroll for Log Window
        self.text_area.bind("<MouseWheel>", self._on_log_scroll)
        self.text_area.bind("<Button-4>", self._on_log_scroll)
        self.text_area.bind("<Button-5>", self._on_log_scroll)

        self.btn_frame = tk.Frame(self, bg=COLOR_BG, pady=20)
        self.btn_frame.pack(fill="x")
        btn_cfg = {"font": ("Arial", 10, "bold"), "relief": "flat", "fg": "white", "padx": 25, "pady": 8, "cursor": "hand2"}
        
        # Instant Cancel (No Popup)
        self.cancel_btn = tk.Button(self.btn_frame, text="CANCEL", command=self.do_instant_cancel, bg=COLOR_DANGER, **btn_cfg)
        self.cancel_btn.pack(side="left", padx=(180, 10))
        self.close_btn = tk.Button(self.btn_frame, text="CLOSE", command=self.destroy, state="disabled", bg="#cccccc", **btn_cfg)
        self.close_btn.pack(side="left", padx=10)

    def _on_log_scroll(self, event):
        if event.num == 4 or event.delta > 0: self.text_area.yview_scroll(-1, "units")
        elif event.num == 5 or event.delta < 0: self.text_area.yview_scroll(1, "units")
        return "break"

    def log(self, msg): self.text_area.insert(tk.END, msg); self.text_area.see(tk.END)

    def do_instant_cancel(self):
        self.cancel_callback()
        self.log("\n🛑 PROCESS TERMINATED INSTANTLY\n")
        self.cancel_btn.config(state="disabled", bg="#cccccc")

    def finalize(self):
        self.finished = True; self.progress.stop(); self.progress.config(mode='determinate', value=100)
        self.label.config(text="✔ DONE: System Cleaned", fg=COLOR_IMPORT)
        self.cancel_btn.config(state="disabled", bg="#cccccc")
        self.close_btn.config(state="normal", bg=COLOR_EXPORT)

    def on_attempt_close(self):
        if self.finished: self.destroy()
        else: messagebox.showwarning("Busy", "Process running. Use Cancel to stop.")

class LinuxSweep:
    def __init__(self, root, pm_type):
        self.root = root
        self.pm_type = pm_type.upper()
        self.root.title(f"LinuxSweep - {self.pm_type}")
        self.root.geometry("1000x800")
        self.root.configure(bg=COLOR_BG)
        self.icon_cache, self.app_data_map, self.selection_vars, self.row_data = {}, {}, {}, {}
        self.log_queue = queue.Queue()
        self.current_proc = None
        self.is_cancelled = False
        self.setup_ui()
        self.refresh_app_list()
        self.check_queue()

    def setup_ui(self):
        style = ttk.Style(); style.theme_use('clam')
        top = tk.Frame(self.root, bg=COLOR_BG, padx=25, pady=20); top.pack(fill="x")
        btn_cfg = {"font": ("Arial", 10, "bold"), "relief": "flat", "fg": "white", "padx": 18, "pady": 6, "cursor": "hand2"}
        tk.Button(top, text="Import Preset", bg=COLOR_IMPORT, command=self.import_preset, **btn_cfg).pack(side="left", padx=5)
        tk.Button(top, text="Export Preset", bg=COLOR_EXPORT, command=self.export_preset, **btn_cfg).pack(side="left", padx=5)
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_display())
        search_unit = tk.Frame(top, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER)
        search_unit.pack(side="left", fill="x", expand=True, padx=(20, 5))
        self.search_entry = tk.Entry(search_unit, textvariable=self.search_var, font=("Arial", 11), relief="flat", bg=COLOR_BG, borderwidth=0, highlightthickness=0)
        self.search_entry.pack(side="left", fill="x", expand=True, padx=(10, 5), ipady=5)
        tk.Frame(search_unit, width=1, bg=COLOR_BORDER).pack(side="left", fill="y")
        tk.Button(search_unit, text="✕", font=("Arial", 10, "bold"), relief="flat", bg=COLOR_BG, fg="gray", width=4, command=lambda: self.search_var.set("")).pack(side="right")
        self.container = tk.Frame(self.root, bg=COLOR_BG); self.container.pack(fill="both", expand=True, padx=25)
        self.canvas = tk.Canvas(self.container, highlightthickness=0, bg=COLOR_BG)
        self.scrollbar = ttk.Scrollbar(self.container, orient="vertical", command=self.canvas.yview)
        self.list_inner = tk.Frame(self.canvas, bg=COLOR_BG)
        self.inner_window = self.canvas.create_window((0, 0), window=self.list_inner, anchor="nw")
        self.canvas.bind('<Configure>', lambda e: self.canvas.itemconfig(self.inner_window, width=e.width))
        self.list_inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True); self.scrollbar.pack(side="right", fill="y")
        
        # Territory-Aware Scrolling
        self.canvas.bind_all("<MouseWheel>", self._on_mousewheel)
        self.canvas.bind_all("<Button-4>", self._on_mousewheel)
        self.canvas.bind_all("<Button-5>", self._on_mousewheel)

        footer = tk.Frame(self.root, bg=COLOR_BG, padx=25, pady=20); footer.pack(fill="x")
        self.status_lbl = tk.Label(footer, text="0 apps selected", bg=COLOR_BG, fg="gray", font=("Arial", 10))
        self.status_lbl.pack(side="left")
        
        # New "Exit" and Improved Naming
        tk.Button(footer, text="EXIT", bg=COLOR_EXPORT, command=self.root.destroy, **btn_cfg).pack(side="right", padx=(10, 0))
        tk.Button(footer, text="UNINSTALL", bg=COLOR_DANGER, command=self.show_confirm, **btn_cfg).pack(side="right")

    def _on_mousewheel(self, event):
        """Only scrolls main list if mouse is over it"""
        if str(event.widget).startswith(str(self.canvas)) or str(event.widget).startswith(str(self.list_inner)):
            if event.num == 4 or event.delta > 0: self.canvas.yview_scroll(-1, "units")
            elif event.num == 5 or event.delta < 0: self.canvas.yview_scroll(1, "units")

    def find_icon(self, name):
        if not name: return None
        if os.path.isabs(name) and os.path.exists(name): return name
        paths = ["/usr/share/icons/hicolor/48x48/apps", "/usr/share/pixmaps", "/usr/share/icons/Adwaita/48x48/apps", "/var/lib/flatpak/exports/share/icons/hicolor/48x48/apps", "/var/lib/snapd/desktop/icons"]
        for r in paths:
            if not os.path.exists(r): continue
            for e in [".png", ".svg", ".xpm"]:
                fp = os.path.join(r, f"{name}{e}")
                if os.path.exists(fp): return fp
        return None

    def get_bulk_owners(self, paths):
        owners = {}
        if not paths: return owners
        try:
            if "APT" in self.pm_type:
                res = subprocess.run(["dpkg", "-S"] + paths, capture_output=True, text=True).stdout
                for l in res.splitlines():
                    if ":" in l: pkg, path = l.split(": ", 1); owners[path.strip()] = pkg.strip()
            elif "DNF" in self.pm_type or "ZYPPER" in self.pm_type:
                res = subprocess.run(["rpm", "-qf", "--qf", "%{NAME}\n"] + paths, capture_output=True, text=True).stdout
                pkgs = res.splitlines()
                for i, path in enumerate(paths):
                    if i < len(pkgs): owners[path] = pkgs[i]
            elif "PACMAN" in self.pm_type:
                res = subprocess.run(["pacman", "-Qqo"] + paths, capture_output=True, text=True).stdout
                pkgs = res.splitlines()
                for i, path in enumerate(paths):
                    if i < len(pkgs): owners[path] = pkgs[i]
        except: pass
        return owners

    def refresh_app_list(self):
        self.app_data_map, all_files = {}, []
        sys_paths = ["/usr/share/applications", "/usr/local/share/applications", os.path.expanduser("~/.local/share/applications")]
        for d in sys_paths:
            if os.path.exists(d): all_files.extend([os.path.join(d, f) for f in os.listdir(d) if f.endswith(".desktop")])
        owners = self.get_bulk_owners(all_files)
        for path in all_files:
            pkg_id = owners.get(path) or os.path.basename(path).replace(".desktop", "")
            try:
                name, icon = "", ""
                with open(path, 'r', errors='ignore') as f:
                    for l in f:
                        if l.startswith("Name="): name = l.split("=")[1].strip()
                        if l.startswith("Icon="): icon = l.split("=")[1].strip()
                uid = f"{pkg_id}_{self.pm_type}"
                if uid not in self.app_data_map:
                    self.app_data_map[uid] = {"name": name or pkg_id, "id": pkg_id, "icon": icon, "pm": self.pm_type}
            except: continue
        try:
            fp_raw = subprocess.check_output(["flatpak", "list", "--columns=name,application,icon"], stderr=subprocess.DEVNULL).decode()
            for line in fp_raw.strip().split('\n'):
                p = line.split('\t')
                if len(p) >= 2:
                    uid = f"{p[1]}_FLATPAK"
                    self.app_data_map[uid] = {"name": p[0], "id": p[1], "icon": p[2] if len(p)>2 else "", "pm": "FLATPAK"}
        except: pass
        try:
            snaps = subprocess.check_output(["snap", "list"], stderr=subprocess.DEVNULL).decode().splitlines()[1:]
            for s in snaps:
                parts = s.split()
                if len(parts) >= 1:
                    sid = parts[0]
                    if sid in ["snapd", "core", "bare"]: continue
                    uid = f"{sid}_SNAP"; self.app_data_map[uid] = {"name": sid.capitalize(), "id": sid, "icon": sid, "pm": "SNAP"}
        except: pass
        self.refresh_display()

    def refresh_display(self):
        for w in self.list_inner.winfo_children(): w.destroy()
        self.row_data = {}
        query = self.search_var.get().lower()
        for uid in sorted(self.app_data_map.keys(), key=lambda k: self.app_data_map[k]['name'].lower()):
            app = self.app_data_map[uid]
            if query in app['name'].lower() or query in app['id'].lower():
                is_p = any(p in app['id'].lower() for p in PROTECTED)
                row = tk.Frame(self.list_inner, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER, padx=12, pady=0)
                row.pack(fill="x", pady=1, padx=5)
                var = self.selection_vars.get(uid, tk.BooleanVar()); self.selection_vars[uid] = var
                tk.Label(row, text="▣" if var.get() else "□", font=("Arial", 16), bg=COLOR_BG, fg=COLOR_ACCENT if var.get() else COLOR_BORDER, width=2).pack(side="left")
                icon_path = self.find_icon(app['icon'])
                if icon_path:
                    try:
                        img = Image.open(icon_path).resize((22, 22), Image.Resampling.LANCZOS)
                        self.icon_cache[icon_path] = ImageTk.PhotoImage(img)
                        tk.Label(row, image=self.icon_cache[icon_path], bg=COLOR_BG).pack(side="left", padx=10)
                    except: pass
                tk.Label(row, text=f"{app['name']} ({app['id']})", fg="red" if is_p else COLOR_TEXT, bg=COLOR_BG, font=("Arial", 9)).pack(side="left")
                pm_lbl = tk.Label(row, text=f"[{app['pm']}]", fg=COLOR_ACCENT if app['pm'] != "SNAP" else "#FF9800", bg=COLOR_BG, font=("Arial", 7, "bold"))
                pm_lbl.pack(side="right", padx=15)
                self.row_data[uid] = row
                if not is_p:
                    for w in row.winfo_children(): w.bind("<Button-1>", lambda e, u=uid: self.toggle_app(u))
                    row.bind("<Button-1>", lambda e, u=uid: self.toggle_app(u))
                if var.get(): self.update_row_ui(uid)

    def update_row_ui(self, uid):
        sel = self.selection_vars[uid].get(); color = COLOR_SELECTED if sel else COLOR_BG
        self.row_data[uid].config(bg=color)
        for w in self.row_data[uid].winfo_children():
            w.config(bg=color)
            if isinstance(w, tk.Label) and len(w.cget("text")) <= 2:
                w.config(text="▣" if sel else "□", fg=COLOR_ACCENT if sel else COLOR_BORDER)

    def toggle_app(self, uid):
        self.selection_vars[uid].set(not self.selection_vars[uid].get())
        self.update_row_ui(uid); self.root.focus_set()
        count = sum(1 for v in self.selection_vars.values() if v.get())
        self.status_lbl.config(text=f"{count} apps selected")

    def export_preset(self):
        ids = [self.app_data_map[uid]['id'] for uid, v in self.selection_vars.items() if v.get()]
        if not ids: return
        p = filedialog.asksaveasfilename(initialdir=USER_HOME, defaultextension=".json", filetypes=[("JSON", "*.json")])
        if p:
            with open(p, 'w') as f: json.dump(ids, f, indent=4)
            messagebox.showinfo("Success", f"Exported {len(ids)} applications.")

    def import_preset(self):
        p = filedialog.askopenfilename(initialdir=USER_HOME, filetypes=[("JSON", "*.json")])
        if not p: return
        with open(p, 'r') as f: imp = json.load(f)
        count = 0
        for uid, app in self.app_data_map.items():
            if app['id'] in imp: self.selection_vars[uid].set(True); count += 1; self.update_row_ui(uid)
        messagebox.showinfo("Success", f"Imported {count} apps.")

    def abort_uninstall(self):
        """Kills process group immediately"""
        self.is_cancelled = True
        if self.current_proc:
            try: os.killpg(os.getpgid(self.current_proc.pid), signal.SIGTERM)
            except: self.current_proc.terminate()

    def check_queue(self):
        try:
            while True:
                msg = self.log_queue.get_nowait()
                if msg == "DONE": self.lw.finalize(); self.refresh_app_list()
                else: self.lw.log(msg)
        except queue.Empty: pass
        self.root.after(100, self.check_queue)

    def show_confirm(self):
        sel = [uid for uid, v in self.selection_vars.items() if v.get()]
        if sel: CustomConfirm(self.root, len(sel), lambda: self.start_uninstall(sel))

    def start_uninstall(self, uids):
        self.is_cancelled = False
        self.lw = LogWindow(self.root, self.abort_uninstall)
        threading.Thread(target=self.worker_thread, args=(uids,), daemon=True).start()

    def worker_thread(self, uids):
        native, flatpak, snap = [], [], []
        for uid in uids:
            app = self.app_data_map[uid]
            if app['pm'] == "FLATPAK": flatpak.append(app['id'])
            elif app['pm'] == "SNAP": snap.append(app['id'])
            else: native.append(app['id'])

        def run_proc(cmd):
            if self.is_cancelled: return
            self.current_proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
            for l in self.current_proc.stdout:
                if self.is_cancelled: break
                self.log_queue.put(l)
            self.current_proc.wait(); self.current_proc = None

        if native:
            cmd_map = {
                "APT": ["apt-get", "purge", "-y", "--auto-remove"],
                "DNF": ["dnf", "remove", "-y", "--setopt=clean_requirements_on_remove=1"],
                "PACMAN": ["pacman", "-Rns", "--noconfirm"],
                "ZYPPER": ["zypper", "remove", "-y", "--clean-deps"]
            }
            run_proc(cmd_map.get(self.pm_type, ["echo", "Unknown PM"]) + native)

        if flatpak and not self.is_cancelled: run_proc(["flatpak", "uninstall", "-y"] + flatpak)
        if snap and not self.is_cancelled:
            for s in snap:
                if self.is_cancelled: break
                self.log_queue.put(f"Surgically removing snap: {s}...\n")
                run_proc(["snap", "remove", "--purge", s])
        self.log_queue.put("DONE")

if __name__ == "__main__":
    root = tk.Tk(); app = LinuxSweep(root, sys.argv[1]); root.mainloop()
EOF

# ----------- 5. EXECUTION -----------
python3 "$PY_FILE" "$PM_TYPE"
rm "$PY_FILE"
