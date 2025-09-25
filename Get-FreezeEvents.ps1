<#  Get-FreezeEvents.ps1 (SMART + GPU + Detail Dumps)
    Collects likely freeze-related events from System/Application logs,
    can auto-focus around latest Kernel-Power 41, checks SMART disk health,
    summarizes GPU driver resets/errors, and dumps details for Kernel-PnP 219
    and Universal Print ID 1 events.

    Examples:
      .\Get-FreezeEvents.ps1 -AroundLastKernelPower
      .\Get-FreezeEvents.ps1 -AroundLastKernelPower -WindowMinutes 15
      .\Get-FreezeEvents.ps1 -HoursBack 24
      .\Get-FreezeEvents.ps1 -From "2025-09-24 16:30" -To "2025-09-24 21:40"
#>

param(
  [int]$HoursBack = 12,
  [Nullable[datetime]]$From = $null,
  [Nullable[datetime]]$To   = $null,
  [switch]$AroundLastKernelPower,
  [int]$WindowMinutes = 5
)

function Get-TimeWindow {
  param(
    [Nullable[datetime]]$From,
    [Nullable[datetime]]$To,
    [switch]$AroundLastKernelPower,
    [int]$WindowMinutes,
    [int]$HoursBack
  )

  if ($AroundLastKernelPower) {
    try {
      $kp = Get-WinEvent -FilterHashtable @{
              LogName='System'; Id=41; ProviderName='Microsoft-Windows-Kernel-Power'
            } -MaxEvents 1 -ErrorAction Stop
      if ($kp) {
        $center = $kp.TimeCreated
        Write-Host ("Focusing on latest Kernel-Power 41 at {0}" -f $center) -ForegroundColor Yellow
        return @($center.AddMinutes(-$WindowMinutes), $center.AddMinutes($WindowMinutes))
      } else {
        Write-Host "No Kernel-Power 41 found. Using HoursBack." -ForegroundColor DarkYellow
      }
    } catch {
      Write-Host "Could not query Kernel-Power 41. Using HoursBack." -ForegroundColor DarkYellow
    }
  }

  if (-not $From) { $From = (Get-Date).AddHours(-$HoursBack) }
  if (-not $To)   { $To   = Get-Date }
  return @($From, $To)
}

function Get-SMARTStatus {
  <#
    Returns a table of disk SMART predict-failure + basic info.
    Some systems/drivers don’t expose MSStorageDriver_* classes; we handle that.
  #>
  $result = @()
  try {
    $drives = Get-CimInstance Win32_DiskDrive | Select-Object DeviceID,PNPDeviceID,Model,SerialNumber,Size,InterfaceType,MediaType,Status
  } catch {
    $drives = @()
  }

  $fpStatus = @()
  try {
    $fpStatus = Get-CimInstance -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue |
      Select-Object InstanceName, PredictFailure, Reason
  } catch {}

  foreach ($d in $drives) {
    $match = $null
    if ($fpStatus) {
      $match = $fpStatus | Where-Object {
        ($_.InstanceName -like "*$($d.SerialNumber)*" -and $d.SerialNumber) -or
        ($_.InstanceName -like "*$($d.Model)*")
      } | Select-Object -First 1
      if (-not $match) {
        if ($drives.Count -eq 1 -and $fpStatus.Count -ge 1) { $match = $fpStatus[0] }
      }
    }

    $obj = [pscustomobject]@{
      DeviceID            = $d.DeviceID
      Model               = $d.Model
      Serial              = $d.SerialNumber
      Interface           = $d.InterfaceType
      MediaType           = $d.MediaType
      SizeGB              = if ($d.Size) { [math]::Round($d.Size/1GB,0) } else { $null }
      WMIStatus           = $d.Status
      SMART_PredictFailure= if ($match) { [bool]$match.PredictFailure } else { $null }
      SMART_Reason        = if ($match) { $match.Reason } else { $null }
    }
    $result += $obj
  }

  if (-not $result -or $result.Count -eq 0) {
    try {
      $result = Get-CimInstance Win32_DiskDrive | Select-Object DeviceID,Model,SerialNumber,@{n='SizeGB';e={[math]::Round($_.Size/1GB,0)}},Status,InterfaceType,MediaType
    } catch { $result = @() }
  }
  return $result
}

function Get-GPUResetStats {
  param([datetime]$From,[datetime]$To)

  $stats = [ordered]@{}

  # Display driver reset (any GPU vendor) - Event ID 4101, Provider "Display"
  try {
    $disp = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; Id=4101; StartTime=$From; EndTime=$To} -ErrorAction SilentlyContinue
    $stats['Display 4101 (TDR resets)'] = ($disp | Measure-Object).Count
  } catch { $stats['Display 4101 (TDR resets)'] = 0 }

  # NVIDIA-specific: Provider nvlddmkm, common error ID 14 (and others)
  try {
    $nv = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='nvlddmkm'; StartTime=$From; EndTime=$To} -ErrorAction SilentlyContinue
    $stats['NVIDIA nvlddmkm (all IDs)'] = ($nv | Measure-Object).Count
    $nv14 = $nv | Where-Object Id -eq 14
    $stats['NVIDIA nvlddmkm ID 14'] = ($nv14 | Measure-Object).Count
  } catch {
    $stats['NVIDIA nvlddmkm (all IDs)'] = 0
    $stats['NVIDIA nvlddmkm ID 14'] = 0
  }

  # AMD-specific: Provider amdkmdag/amdkmdap
  foreach ($prov in @('amdkmdag','amdkmdap')) {
    try {
      $amd = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=$prov; StartTime=$From; EndTime=$To} -ErrorAction SilentlyContinue
      $stats["AMD $prov (all IDs)"] = ($amd | Measure-Object).Count
    } catch {
      $stats["AMD $prov (all IDs)"] = 0
    }
  }

  return $stats.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{ Metric = $_.Key; Count = $_.Value }
  }
}

# ---------------------- MAIN ----------------------
$tw = Get-TimeWindow -From $From -To $To -AroundLastKernelPower:$AroundLastKernelPower `
                     -WindowMinutes $WindowMinutes -HoursBack $HoursBack
$From = $tw[0]; $To = $tw[1]

$providers = @(
  'Disk','Ntfs','StorPort','volsnap',
  'Kernel-Power','Kernel-PnP','Kernel-EventTracing','EventLog',
  'Display','nvlddmkm','amdkmdag','WHEA-Logger'
)
$eventIds = @(41,6008,14,4101,129,153,219)

$filters = @(
  @{ LogName='System'; ProviderName=$providers; StartTime=$From; EndTime=$To; Level=1 },
  @{ LogName='System'; ProviderName=$providers; StartTime=$From; EndTime=$To; Level=2 },
  @{ LogName='System'; ProviderName=$providers; StartTime=$From; EndTime=$To; Level=3 },
  @{ LogName='System'; Id=$eventIds; StartTime=$From; EndTime=$To },
  @{ LogName='Application'; Level=1; StartTime=$From; EndTime=$To },
  @{ LogName='Application'; Level=2; StartTime=$From; EndTime=$To }
)

$events = foreach ($f in $filters) { try { Get-WinEvent -FilterHashtable $f -ErrorAction Stop } catch {} }

$rows = $events |
  Sort-Object TimeCreated |
  Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
    @{n='Task';e={$_.TaskDisplayName}},
    @{n='Message';e={$_.Message -replace '\s+',' '}}

$outDir = Join-Path $PSScriptRoot 'FreezeLogs'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outStamp = ("{0:yyyyMMdd_HHmmss}" -f (Get-Date))

# ---- Save primary event table
$outCsv   = Join-Path $outDir ("FreezeEvents_$outStamp.csv")
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv

Write-Host "Window: $From  -->  $To" -ForegroundColor Cyan
Write-Host "Collected $($rows.Count) events." -ForegroundColor Cyan

$rows | Group-Object ProviderName, Id | Sort-Object Count -Descending |
  Select-Object Count,
    @{n='Provider';e={$_.Group[0].ProviderName}},
    @{n='EventID'; e={$_.Group[0].Id}} |
  Format-Table -AutoSize

Write-Host "`nMost recent events:" -ForegroundColor Yellow
$rows | Select-Object -Last 20 | Format-Table TimeCreated,ProviderName,Id,LevelDisplayName -AutoSize

# ---- SMART summary
Write-Host "`n=== SMART Disk Summary ===" -ForegroundColor Magenta
$smart = Get-SMARTStatus
$smart | Format-Table DeviceID,Model,Serial,SizeGB,Interface,MediaType,WMIStatus,SMART_PredictFailure,SMART_Reason -AutoSize
$smartCsv = Join-Path $outDir ("SMART_$outStamp.csv")
$smart | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $smartCsv

# ---- GPU reset stats
Write-Host "`n=== GPU Driver Reset/Error Summary ===" -ForegroundColor Magenta
$gpu = Get-GPUResetStats -From $From -To $To
$gpu | Format-Table -AutoSize
$gpuCsv = Join-Path $outDir ("GPU_$outStamp.csv")
$gpu | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $gpuCsv

# ---- Detailed dumps for Kernel-PnP 219 and Universal Print 1
Write-Host "`n=== Kernel-PnP 219 Details ===" -ForegroundColor Magenta
$kpnps = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-PnP'; Id=219; StartTime=$From; EndTime=$To} -ErrorAction SilentlyContinue
$kpnps | ForEach-Object {
  "`n[$($_.TimeCreated)] $($_.ProviderName) ID=$($_.Id)"
  $_.Message
}
$kpnpsCsv = Join-Path $outDir ("KernelPnP_219_$outStamp.csv")
$kpnps | Select-Object TimeCreated, Id, ProviderName, Message | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $kpnpsCsv

# ---- Robust Universal Print (ID 1) dump (no ProviderName in filter)
Write-Host "`n=== Universal Print (ID 1) Details ===" -ForegroundColor Magenta
$up = @()
try {
  # 1) Get all System events with ID 1 in the window (fast), then filter by provider name variants
  $cand = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=1; StartTime=$From; EndTime=$To } -ErrorAction SilentlyContinue

  # 2) Keep only those that look like Universal Print
  #    Some builds show ProviderName exactly "Universal Print", others use variations.
  $up = $cand | Where-Object {
    $_.ProviderName -match '(?i)universal\s*print|printworkflow|cloud\s*print'
  }

  # 3) If nothing found (rare), try Applications and Services logs for Universal Print channels
  if (-not $up -or $up.Count -eq 0) {
    $channels = @(
      'Microsoft-Windows-PrintWorkflow/Operational',
      'Microsoft-Universal-Print/Operational',
      'Microsoft-Windows-PrintService/Admin',
      'Microsoft-Windows-PrintService/Operational'
    )
    foreach ($ch in $channels) {
      try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName=$ch; StartTime=$From; EndTime=$To } -ErrorAction SilentlyContinue
        if ($ev) {
          # keep only obvious Universal Print / workflow errors
          $up += ($ev | Where-Object { $_.Id -eq 1 -or $_.Message -match '(?i)universal\s*print|cloud\s*print|workflow' })
        }
      } catch {}
    }
  }
} catch {}

# Console preview (cap it so the console doesn’t flood)
$up | Select-Object -First 8 | ForEach-Object {
  "`n[$($_.TimeCreated)] $($_.ProviderName) ID=$($_.Id)"
  $_.Message
}

# Save full details
$upCsv = Join-Path $outDir ("UniversalPrint_1_$outStamp.csv")
$up | Select-Object TimeCreated, Id, ProviderName, LogName, Message |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $upCsv


Write-Host "`nSaved details to:" -ForegroundColor Green
Write-Host "  $outCsv" -ForegroundColor Green
Write-Host "  $smartCsv" -ForegroundColor Green
Write-Host "  $gpuCsv" -ForegroundColor Green
Write-Host "  $kpnpsCsv" -ForegroundColor Green
Write-Host "  $upCsv" -ForegroundColor Green
