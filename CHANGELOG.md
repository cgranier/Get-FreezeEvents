\# Changelog



All notable changes to \*\*Get-FreezeEvents\*\* will be documented in this file.



The format is based on \[Keep a Changelog](https://keepachangelog.com/en/1.1.0/),

and this project adheres to \[Semantic Versioning](https://semver.org/spec/v2.0.0.html).



---



\## \[Unreleased]

\- \[ ] Add ETW capture option around freeze events

\- \[ ] Add optional HTML report generation

\- \[ ] Add perf counter stats (disk queue, GPU utilization) for window



---



\## \[1.0.0] - 2025-09-25

\### Added

\- Initial release of \*\*Get-FreezeEvents.ps1\*\*

\- Collects events tied to system freezes (Critical, Error, Warning)

\- Auto-focus around last \*\*Kernel-Power 41\*\* (`-AroundLastKernelPower`)

\- SMART disk health summary with fallback when classes missing

\- GPU reset/error summary (Display 4101, NVIDIA nvlddmkm, AMD amdkmdag|amdkmdap)

\- Full detail dumps for:

&nbsp; - \*\*Kernel-PnP 219\*\* (driver/device timeout handoffs)

&nbsp; - \*\*Universal Print (ID 1)\*\* errors

\- Export to CSV files in `FreezeLogs/`

\- Human-readable console summaries for quick triage



---



\## \[0.1.0] - 2025-09-20

\### Prototype

\- Early script testing in PowerShell

\- Manual filtering for Kernel-Power 41, Disk, GPU, and SMART



