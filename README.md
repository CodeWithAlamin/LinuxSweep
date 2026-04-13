# 🧹 LinuxSweep

**The ultimate debloater for Linux distributions.**

LinuxSweep is a lightweight, nice GUI utility designed to help you reclaim your system by purging unwanted pre-installed applications. Built with a focus on speed and a clean, high-density interface, it allows you to "sweep" your distro clean in seconds.

---

## ✨ Key Features

* **🚀 Cross-Distro Support:** Seamlessly works with **APT**, **DNF**, **Pacman**, and **Zypper**.
* **📦 Flatpak/Snap Integration:** Automatically detects flatpak and snap applications.
* **🔍 Search:** Easy search functionality.
* **💾 Preset Management:** Import and Export your custom debloat lists as `.json` files.
* **🚀 Present Merging:** Easily merge multiple presets.

---

![LinuxSweep](./thumbnail.png)

---

## 🛠️ Requirements

To run LinuxSweep, ensure you have the following dependencies installed (the script will attempt to install them for you if missing):

* **Python 3**
* **Tkinter** (Python GUI library)

---

## 🚀 Installation & Usage

### ⚡ Quick Run
```bash
curl -fsSL https://raw.githubusercontent.com/CodeWithAlamin/LinuxSweep/refs/heads/main/linux_sweep.sh | bash
````

### 🛠️ Standard Installation

1.  **Clone the repository and go to the directory:**

    ```bash
    git clone https://github.com/CodeWithAlamin/LinuxSweep.git
    cd LinuxSweep
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x linux_sweep.sh
    ```

3.  **Run it:**

    ```bash
    ./linux_sweep.sh
    ```

    *Note: The app uses Polkit (pkexec) to ask for your password via a standard system pop-up for necessary root actions.*

-----

## 📂 Presets

LinuxSweep uses a simple JSON format for presets.

**Example `debloat.json`:**

```json
[
    "gnome-weather",
    "org.gnome.Maps",
    "cheese"
]
```

When importing, LinuxSweep automatically scans your system and selects only the apps that are actually installed.

-----

## 🤝 Contributing

Contributions are welcome\! If you have ideas for new features or UI improvements, feel free to open an issue or submit a pull request.

-----

## 👨‍💻 Developed By

**Alamin**

- **GitHub:** [@CodeWithAlamin](https://github.com/CodeWithAlamin)
- **LinkedIn:** [CodeWithAlamin](https://www.linkedin.com/in/CodeWithAlamin)
- **X (Twitter):** [@CodeWithAlamin](https://x.com/CodeWithAlamin)

-----

**Sweep your Linux system clean with LinuxSweep\!** 🐧✨
