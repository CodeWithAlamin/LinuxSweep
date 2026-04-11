# 🧹 LinuxSweep

**The ultimate high-density, surgical debloater for Linux distributions.**

LinuxSweep is a lightweight, professional GUI utility designed to help you reclaim your system by purging unwanted pre-installed applications and Flatpaks. Built with a focus on speed and a clean, high-density interface, it allows you to "sweep" your distro clean in seconds.

---

## ✨ Key Features

* **🚀 Cross-Distro Support:** Seamlessly works with **APT**, **DNF**, **Pacman**, and **Zypper**.
* **📦 Flatpak Integration:** Automatically detects and uninstalls Flatpak applications alongside native packages.
* **🔍 Search:** A unit-styled, borderless flexible search bar.
* **💾 Preset Management:** Import and Export your custom debloat lists as `.json` files to replicate your perfect setup on any machine.

---

## 📸 Screenshots



---

## 🛠️ Requirements

To run LinuxSweep, ensure you have the following dependencies installed (the script will attempt to install them for you if missing):

* **Python 3**
* **Tkinter** (Python GUI library)
* **Pillow** (Python Imaging Library for icons)

---

## 🚀 Installation & Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/LinuxSweep.git
    cd LinuxSweep
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x linux_sweep.sh
    ```

3.  **Run it:**
    You can double-click `linux_sweep.sh` in your file manager or run it from the terminal:
    ```bash
    ./linux_sweep.sh
    ```
    *No `sudo` is required in the command; the app will ask for your password via a standard system pop-up.*

---

## 📂 Presets

LinuxSweep uses a simple JSON format for presets. This makes it easy to share your "Debloat Lists" with the community.

**Example `debloat.json`:**
```json
[
    "gnome-weather",
    "org.gnome.Maps",
    "cheese",
]
```

When importing, LinuxSweep automatically scans your system and selects only the apps that are actually installed, providing a summary notification upon completion.

---

## 🤝 Contributing

Contributions are welcome! If you have ideas for new features or UI improvements, feel free to open an issue or submit a pull request.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---

## ⚖️ License

Distributed under the MIT License. See `LICENSE` for more information.

---

## 👨‍💻 Developed By

**Alamin**

- **GitHub:** [@CodeWithAlamin](https://github.com/CodeWithAlamin)
- **LinkedIn:** [CodeWithAlamin](https://www.linkedin.com/in/CodeWithAlamin)
- **X (Twitter):** [@CodeWithAlamin](https://x.com/CodeWithAlamin)

---

**Sweep your Linux system clean with LinuxSweep!** 🐧✨
