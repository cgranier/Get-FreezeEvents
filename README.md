# Get-FreezeEvents

A focused Windows forensics helper that pulls the **events most likely related to system freezes**, optionally auto-centers the search around your **last Kernel-Power 41** (unexpected shutdown), and adds quick **SMART disk health** and **GPU driver reset** summaries. It also dumps **Kernel-PnP 219** details (device/driver timeouts) and **Universal Print** noise for easier diagnosis.

> Tested on Windows 10/11 with PowerShell 5+ (Windows PowerShell).  
> Run from an **elevated PowerShell** (Run as Administrator) for best results.

---

## ✨ Features

- **Time-window focus**
  - `-AroundLastKernelPower` → auto-find the latest **Event ID 41** and analyze ± *N* minutes.
  - Or specify a window with `-From` / `-To` or `-HoursBack`.

- **Event filtering that matters**
  - System/Application logs: Critical, Error, Warning from providers commonly tied to freezes.
  - Extra include: specific IDs like **41, 6008, 14, 4101, 129, 153, 219**.

- **Hardware signals**
  - **SMART** summary via WMI/CIM (falls back gracefully if classes aren’t exposed).
  - **GPU** reset/error counters: Display 4101 (TDR), NVIDIA `nvlddmkm`, AMD `amdkmdag|amdkmdap`.

- **Deep-dive dumps**
  - Full **Kernel-PnP 219** messages (device instance paths & status codes).
  - Robust **Universal Print (ID 1)** capture (handles provider name quirks).

- **Exports**
  - CSVs with all findings in a `FreezeLogs/` folder, plus human-readable console tables.

---

## 📥 Installation

No modules required.

1. Save the script as `Get-FreezeEvents.ps1`.
2. Open **PowerShell as Administrator**.
3. (Optional) Allow local scripts:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

---

## 🚀 Quick Start

Analyze the last freeze automatically (±5 minutes around the last Kernel-Power 41):

```powershell
.\Get-FreezeEvents.ps1 -AroundLastKernelPower
```

Go wider (±15 minutes):

```powershell
.\Get-FreezeEvents.ps1 -AroundLastKernelPower -WindowMinutes 15
```

Look back 24 hours:

```powershell
.\Get-FreezeEvents.ps1 -HoursBack 24
```

Custom window:

```powershell
.\Get-FreezeEvents.ps1 -From "2025-09-24 16:30" -To "2025-09-24 21:40"
```

---

## ⚙️ Parameters

| Param | Type | Default | Description |
|---|---|---:|---|
| `-HoursBack` | `int` | 12 | Analyze the last *N* hours (used if `-From/-To` not given and `-AroundLastKernelPower` not used or not found). |
| `-From` | `datetime?` |  | Start of the window (UTC/local accepted). |
| `-To` | `datetime?` |  | End of the window. |
| `-AroundLastKernelPower` | `switch` |  | Find the most recent **Event ID 41** and center the window (± `WindowMinutes`). |
| `-WindowMinutes` | `int` | 5 | Half-width of the time window when using `-AroundLastKernelPower`. |

---

## 📄 Output

All files are written to `FreezeLogs\` (created next to the script):

- `FreezeEvents_YYYYMMDD_HHMMSS.csv` – all collected events in the window.
- `SMART_YYYYMMDD_HHMMSS.csv` – disk model/serial/size + predict-failure status when available.
- `GPU_YYYYMMDD_HHMMSS.csv` – counts of GPU resets/errors per provider/ID.
- `KernelPnP_219_YYYYMMDD_HHMMSS.csv` – full text of **Event ID 219** messages.
- `UniversalPrint_1_YYYYMMDD_HHMMSS.csv` – Universal Print / Print Workflow errors captured.

The console also prints:
- A grouped **summary table** (Provider × EventID × Count).
- A short **“Most recent events”** list.
- SMART and GPU summary tables.

---

## 🧭 Interpreting Results (Cheat Sheet)

- **41 – Kernel-Power (Critical)**: The system didn’t shut down cleanly (freeze, crash, power cut). Use as an anchor.
- **6008 – EventLog**: Previous shutdown was unexpected (confirms 41).
- **4101 – Display**: GPU timeout/recovery (TDR). Frequent 4101s → GPU/driver/power/thermal angle.
- **14 – nvlddmkm**: NVIDIA driver error (vendor-specific). Spikes near freeze → GPU stack.
- **129/153 – StorPort / Kernel-Boot**: Storage timeouts / paging hiccups. Look at disk, cables, controller drivers.
- **219 – Kernel-PnP**: Device/driver failed to start (often **WUDFRd** handoffs for USB/HID/Thunderbolt/biometrics). These frequently line up with resume/boot stalls.

**SMART `PredictFailure=True`** on any drive → **back up immediately** and replace that disk.

---

## 🔧 Troubleshooting

- **“No events were found…”**: Widen your window (`-HoursBack 24` or bigger `-WindowMinutes`).
- **SMART block says “operation not supported”**: Your storage driver doesn’t expose the MSStorageDriver_* classes. The script falls back to `Win32_DiskDrive`.
- **Access errors**: Run PowerShell **as Administrator**.
- **CSV shows tons of Universal Print errors**: Likely noise after a crash. Consider disabling/removing Universal Print/Workflow if you don’t use it.

---

## 🔐 Privacy

The script reads **local Windows event logs** and **hardware info via WMI/CIM**.  
All data stays on your machine unless you share the generated CSVs.

---

## 🗺️ Roadmap

- Optional ETW capture pre-/post-freeze (lightweight trace).
- Optional perf counters (disk queue length, GPU utilization) during window.
- HTML report generation.

---

## 🤝 Contributing

PRs welcome! Please:
- Keep the script compatible with Windows PowerShell 5.1+.
- Avoid external dependencies where possible.
- Gracefully handle missing providers/log channels.

---

## 📄 License

MIT — do what you want, but no warranty. See `LICENSE`.

---

## ✅ Suggested Repo Structure

```
Get-FreezeEvents/
├─ Get-FreezeEvents.ps1
├─ README.md
├─ LICENSE
└─ .gitignore
```

**Tip:** add `FreezeLogs/` to `.gitignore` if you don’t want generated CSVs committed.
