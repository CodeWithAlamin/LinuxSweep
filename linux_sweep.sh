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

# ----------- 3. THE PYTHON ENGINE -----------
PY_FILE="/tmp/linux_sweep_engine.py"

cat << 'EOF' > "$PY_FILE"
import os, sys, json, subprocess, tkinter as tk
from tkinter import ttk, messagebox, filedialog
from PIL import Image, ImageTk
import threading
import queue
import pwd

PROTECTED = ["python3", "python", "python3-tk", "python3-pil", "pillow", "tkinter", "pkexec"]

# Modern Color Palette
COLOR_BG = "#ffffff"
COLOR_HOVER = "#f8f9fa"
COLOR_SELECTED = "#e7f3ff"
COLOR_BORDER = "#cccccc" # Slightly darker for clarity
COLOR_TEXT = "#333333"
COLOR_IMPORT = "#4caf50" 
COLOR_EXPORT = "#607d8b" 
COLOR_DANGER = "#f44336" 
COLOR_ACCENT = "#1976d2"

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
        self.transient(parent)
        self.grab_set()
        self.callback = callback
        f = tk.Frame(self, bg=COLOR_BG); f.pack(expand=True)
        tk.Label(f, text="⚠ Confirm Action", font=("Arial", 14, "bold"), bg=COLOR_BG, fg=COLOR_DANGER).pack(pady=(0, 15))
        tk.Label(f, text=f"Uninstall {count} selected applications?", font=("Arial", 11), bg=COLOR_BG, fg=COLOR_TEXT).pack(pady=10)
        btn_f = tk.Frame(f, bg=COLOR_BG, pady=20); btn_f.pack()
        cfg = {"font": ("Arial", 10, "bold"), "relief": "flat", "fg": "white", "padx": 25, "pady": 8, "cursor": "hand2"}
        tk.Button(btn_f, text="CANCEL", bg=COLOR_EXPORT, command=self.destroy, **cfg).pack(side="left", padx=10)
        tk.Button(btn_f, text="UNINSTALL", bg=COLOR_DANGER, command=self.confirm, **cfg).pack(side="left", padx=10)
    def confirm(self): self.destroy(); self.callback()

class LogWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title("LinuxSweep Logs")
        self.geometry("750x600")
        self.configure(bg=COLOR_BG)
        self.protocol("WM_DELETE_WINDOW", self.on_attempt_close)
        self.finished = False
        self.label = tk.Label(self, text="Processing Tasks...", font=("Arial", 12, "bold"), bg=COLOR_BG, fg=COLOR_TEXT, pady=20)
        self.label.pack()
        self.progress = ttk.Progressbar(self, mode='indeterminate', length=650)
        self.progress.pack(pady=5, padx=30); self.progress.start(15)
        self.log_container = tk.Frame(self, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER)
        self.log_container.pack(fill="both", expand=True, padx=30, pady=20)
        self.text_area = tk.Text(self.log_container, bg="#fafafa", fg=COLOR_TEXT, font=("Monospace", 9), relief="flat", padx=15, pady=15)
        self.scrollbar = ttk.Scrollbar(self.log_container, orient="vertical", command=self.text_area.yview)
        self.text_area.configure(yscrollcommand=self.scrollbar.set)
        self.text_area.pack(side="left", fill="both", expand=True); self.scrollbar.pack(side="right", fill="y")
        self.close_btn = tk.Button(self, text="CLOSE WINDOW", command=self.destroy, state="disabled", font=("Arial", 10, "bold"), relief="flat", bg="#cccccc", fg="white", padx=25, pady=8, cursor="hand2")
        self.close_btn.pack(pady=20)
    def log(self, msg): self.text_area.insert(tk.END, msg); self.text_area.see(tk.END)
    def finalize(self):
        self.finished = True; self.progress.stop(); self.progress.config(mode='determinate', value=100)
        self.label.config(text="✔ DONE: System Swept Clean", fg=COLOR_IMPORT)
        self.close_btn.config(state="normal", bg=COLOR_EXPORT)
    def on_attempt_close(self):
        if self.finished: self.destroy()
        else: messagebox.showwarning("Busy", "Process is still running.")

class LinuxSweep:
    def __init__(self, root, pm_type):
        self.root = root
        self.pm_type = pm_type.upper()
        self.root.title(f"LinuxSweep - {self.pm_type}")
        self.root.geometry("1000x800")
        self.root.configure(bg=COLOR_BG)
        self.icon_cache, self.app_data_map, self.selection_vars, self.row_data = {}, {}, {}, {}
        self.log_queue = queue.Queue()
        self.setup_ui()
        self.refresh_app_list()
        self.check_queue()

    def setup_ui(self):
        # 1. Top Bar with Reordered Buttons and Unified Search
        top = tk.Frame(self.root, bg=COLOR_BG, padx=25, pady=20); top.pack(fill="x")
        btn_cfg = {"font": ("Arial", 10, "bold"), "relief": "flat", "fg": "white", "padx": 18, "pady": 6, "cursor": "hand2"}
        
        tk.Button(top, text="Import Preset", bg=COLOR_IMPORT, command=self.import_preset, **btn_cfg).pack(side="left", padx=5)
        tk.Button(top, text="Export Preset", bg=COLOR_EXPORT, command=self.export_preset, **btn_cfg).pack(side="left", padx=5)

        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_display())
        
        # Combined Search Wrapper (Single Border)
        search_unit = tk.Frame(top, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER)
        search_unit.pack(side="left", fill="x", expand=True, padx=(20, 5))
        
        # Inner Entry (No border of its own)
        self.search_entry = tk.Entry(search_unit, textvariable=self.search_var, font=("Arial", 11), relief="flat", bg=COLOR_BG, borderwidth=0, highlightthickness=0)
        self.search_entry.pack(side="left", fill="x", expand=True, padx=(10, 5), ipady=5)
        
        # 1px Vertical Separator
        tk.Frame(search_unit, width=1, bg=COLOR_BORDER).pack(side="left", fill="y")
        
        # Flush Clear Button
        tk.Button(search_unit, text="✕", font=("Arial", 10, "bold"), relief="flat", bg=COLOR_BG, fg="gray", activebackground=COLOR_BG, width=4, cursor="hand2", command=lambda: self.search_var.set("")).pack(side="right")

        # 2. List Container
        self.container = tk.Frame(self.root, bg=COLOR_BG); self.container.pack(fill="both", expand=True, padx=25)
        self.canvas = tk.Canvas(self.container, highlightthickness=0, bg=COLOR_BG)
        self.scrollbar = ttk.Scrollbar(self.container, orient="vertical", command=self.canvas.yview)
        self.list_inner = tk.Frame(self.canvas, bg=COLOR_BG)
        self.inner_window = self.canvas.create_window((0, 0), window=self.list_inner, anchor="nw")
        
        self.canvas.bind('<Configure>', lambda e: self.canvas.itemconfig(self.inner_window, width=e.width))
        self.list_inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True); self.scrollbar.pack(side="right", fill="y")
        
        # Unfocus Search when clicking list
        self.canvas.bind("<Button-1>", lambda e: self.root.focus_set())
        self.list_inner.bind("<Button-1>", lambda e: self.root.focus_set())
        self.canvas.bind_all("<Button-4>", lambda e: self.canvas.yview_scroll(-1, "units"))
        self.canvas.bind_all("<Button-5>", lambda e: self.canvas.yview_scroll(1, "units"))

        # 3. Footer
        footer = tk.Frame(self.root, bg=COLOR_BG, padx=25, pady=20); footer.pack(fill="x")
        self.status_lbl = tk.Label(footer, text="0 apps selected", bg=COLOR_BG, fg="gray", font=("Arial", 10))
        self.status_lbl.pack(side="left")
        tk.Button(footer, text="UNINSTALL SELECTED", bg=COLOR_DANGER, command=self.show_confirm, **btn_cfg).pack(side="right")

    def find_icon(self, name):
        if not name: return None
        if os.path.isabs(name) and os.path.exists(name): return name
        for r in ["/usr/share/icons/hicolor/48x48/apps", "/usr/share/pixmaps", "/usr/share/icons/Adwaita/48x48/apps"]:
            for e in [".png", ".svg", ".xpm"]:
                full_path = os.path.join(r, f"{name}{e}")
                if os.path.exists(full_path): return full_path
        return None

    def refresh_app_list(self):
        self.app_data_map, all_files = {}, []
        for d in ["/usr/share/applications", "/usr/local/share/applications", os.path.expanduser("~/.local/share/applications")]:
            if os.path.exists(d): all_files.extend([os.path.join(d, f) for f in os.listdir(d) if f.endswith(".desktop")])
        owners = self.get_bulk_owners(all_files)
        for path in all_files:
            pkg_id = owners.get(path)
            if pkg_id:
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
            fp = subprocess.check_output(["flatpak", "list", "--columns=name,application,icon"], stderr=subprocess.DEVNULL).decode()
            for line in fp.strip().split('\n'):
                p = line.split('\t')
                if len(p) >= 2:
                    uid = f"{p[1]}_FLATPAK"
                    self.app_data_map[uid] = {"name": p[0], "id": p[1], "icon": p[2] if len(p)>2 else "", "pm": "FLATPAK"}
        except: pass
        self.refresh_display()

    def refresh_display(self):
        """Build high-density list"""
        for w in self.list_inner.winfo_children(): w.destroy()
        self.row_data = {}
        query = self.search_var.get().lower()
        for uid in sorted(self.app_data_map.keys(), key=lambda k: self.app_data_map[k]['name'].lower()):
            app = self.app_data_map[uid]
            if query in app['name'].lower() or query in app['id'].lower():
                is_p = any(p in app['id'] for p in PROTECTED)
                row = tk.Frame(self.list_inner, bg=COLOR_BG, highlightthickness=1, highlightbackground=COLOR_BORDER, padx=12, pady=0)
                row.pack(fill="x", pady=1, padx=5)
                
                var = self.selection_vars.get(uid, tk.BooleanVar())
                self.selection_vars[uid] = var
                check = tk.Label(row, text="□", font=("Arial", 16), bg=COLOR_BG, fg=COLOR_BORDER, width=2)
                check.pack(side="left")
                
                icon_path = self.find_icon(app['icon'])
                icon_lbl = tk.Label(row, bg=COLOR_BG)
                if icon_path:
                    try:
                        img = Image.open(icon_path).resize((22, 22), Image.Resampling.LANCZOS)
                        self.icon_cache[icon_path] = ImageTk.PhotoImage(img)
                        icon_lbl.config(image=self.icon_cache[icon_path])
                    except: pass
                icon_lbl.pack(side="left", padx=10)
                
                name_lbl = tk.Label(row, text=f"{app['name']} ({app['id']})", fg="red" if is_p else COLOR_TEXT, bg=COLOR_BG, font=("Arial", 9))
                name_lbl.pack(side="left")
                
                pm_lbl = tk.Label(row, text=f"[{app['pm']}]", fg=COLOR_ACCENT, bg=COLOR_BG, font=("Arial", 7, "bold"))
                pm_lbl.pack(side="right", padx=15)
                
                self.row_data[uid] = [row, check, icon_lbl, name_lbl, pm_lbl]
                
                if not is_p:
                    for w in self.row_data[uid]:
                        w.bind("<Button-1>", lambda e, u=uid: self.toggle_app(u))
                        w.bind("<Enter>", lambda e, u=uid: self.on_hover(u, True))
                        w.bind("<Leave>", lambda e, u=uid: self.on_hover(u, False))
                if var.get(): self.update_row_ui(uid)

    def on_hover(self, uid, entering):
        if self.selection_vars[uid].get(): return
        color = COLOR_HOVER if entering else COLOR_BG
        for w in self.row_data[uid]: w.config(bg=color)

    def update_row_ui(self, uid):
        sel = self.selection_vars[uid].get()
        color = COLOR_SELECTED if sel else COLOR_BG
        widgets = self.row_data[uid]
        widgets[0].config(bg=color)
        widgets[1].config(text="▣" if sel else "□", fg=COLOR_ACCENT if sel else COLOR_BORDER, bg=color)
        for w in widgets[2:]: w.config(bg=color)

    def toggle_app(self, uid):
        if any(p in uid for p in PROTECTED): return
        self.selection_vars[uid].set(not self.selection_vars[uid].get())
        self.update_row_ui(uid); self.root.focus_set()
        count = sum(1 for v in self.selection_vars.values() if v.get())
        self.status_lbl.config(text=f"{count} apps selected")

    def get_bulk_owners(self, paths):
        owners = {}
        try:
            if "APT" in self.pm_type:
                res = subprocess.run(["dpkg", "-S"] + paths, capture_output=True, text=True).stdout
                for l in res.splitlines():
                    if ":" in l: pkg, path = l.split(": ", 1); owners[path.strip()] = pkg.strip()
        except: pass
        return owners

    def export_preset(self):
        ids = [self.app_data_map[uid]['id'] for uid, v in self.selection_vars.items() if v.get()]
        if not ids: return
        p = filedialog.asksaveasfilename(initialdir=USER_HOME, defaultextension=".json", filetypes=[("JSON files", "*.json")])
        if p:
            with open(p, 'w') as f: json.dump(ids, f, indent=4)
            messagebox.showinfo("Export Success", f"Successfully exported {len(ids)} applications.")

    def import_preset(self):
        p = filedialog.askopenfilename(initialdir=USER_HOME, filetypes=[("JSON files", "*.json")])
        if not p: return
        try:
            with open(p, 'r') as f: imp = json.load(f)
            count = 0
            for uid, app in self.app_data_map.items():
                if app['id'] in imp: self.selection_vars[uid].set(True); count += 1; self.update_row_ui(uid)
            messagebox.showinfo("Import Success", f"Successfully imported {count} applications.")
        except: pass

    def check_queue(self):
        try:
            while True:
                msg = self.log_queue.get_nowait()
                if msg == "DONE": self.lw.finalize(); self.refresh_app_list()
                else: self.lw.log(msg)
        except queue.Empty: pass
        self.root.after(100, self.check_queue)

    def show_confirm(self):
        native = [uid.split('_')[0] for uid, v in self.selection_vars.items() if v.get() and uid.endswith(self.pm_type)]
        flat = [uid.split('_')[0] for uid, v in self.selection_vars.items() if v.get() and uid.endswith("FLATPAK")]
        if native or flat: CustomConfirm(self.root, len(native)+len(flat), lambda: self.worker_start(native, flat))

    def worker_start(self, native, flat):
        self.lw = LogWindow(self.root); threading.Thread(target=self.worker_thread, args=(native, flat), daemon=True).start()

    def worker_thread(self, native, flat):
        if native:
            cmd = {"APT":["apt","purge","-y"],"DNF":["dnf","remove","-y"],"PACMAN":["pacman","-Rns","--noconfirm"],"ZYPPER":["zypper","remove","-y"]}[self.pm_type]
            proc = subprocess.Popen(cmd + native, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for l in proc.stdout: self.log_queue.put(l)
            proc.wait()
        if flat:
            proc = subprocess.Popen(["flatpak", "uninstall", "-y"] + flat, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for l in proc.stdout: self.log_queue.put(l)
            proc.wait()
        self.log_queue.put("DONE")

if __name__ == "__main__":
    root = tk.Tk(); app = LinuxSweep(root, sys.argv[1]); root.mainloop()
EOF

# ----------- 4. EXECUTION -----------
python3 "$PY_FILE" "$PM_TYPE"
rm "$PY_FILE"