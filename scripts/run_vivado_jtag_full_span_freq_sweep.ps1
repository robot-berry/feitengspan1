param(
  [ValidateSet(2, 4)]
  [int]$Scale = 4,
  [ValidateRange(1, 32)]
  [int]$ImgW = 32,
  [int[]]$FrequenciesMhz = @(40, 50, 75, 100, 125, 150),
  [switch]$StopOnFailure,
  [string]$VivadoBat = "D:\software\2025.2\Vivado\bin\vivado.bat",
  [string]$OutCsv = ""
)

$ErrorActionPreference = "Stop"

function Get-FrequencyTag {
  param([int]$FreqMhz)
  if ($FreqMhz -eq 25) {
    return ""
  }
  return "_f${FreqMhz}m"
}

function Get-TimingSummary {
  param([string]$TimingReport)

  if (-not (Test-Path $TimingReport)) {
    return [pscustomobject]@{
      WnsNs = $null
      TnsNs = $null
      WhsNs = $null
      ClockMhz = $null
    }
  }

  $text = [IO.File]::ReadAllText((Resolve-Path $TimingReport))
  $row = [regex]::Match(
    $text,
    "(?s)Design Timing Summary.*?\r?\n\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s+(-?\d+\.\d+)"
  )
  $clock = [regex]::Match(
    $text,
    "(?m)^\s*clk_pl_0\s+\{[^\r\n]+\}\s+\d+\.\d+\s+(\d+\.\d+)"
  )

  return [pscustomobject]@{
    WnsNs = if ($row.Success) { [double]$row.Groups[1].Value } else { $null }
    TnsNs = if ($row.Success) { [double]$row.Groups[2].Value } else { $null }
    WhsNs = if ($row.Success) { [double]$row.Groups[3].Value } else { $null }
    ClockMhz = if ($clock.Success) { [double]$clock.Groups[1].Value } else { $null }
  }
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  if ($OutCsv -eq "") {
    $OutCsv = Join-Path $root ("vivado\reports\jtag_full_span_x{0}_{1}x{1}_freq_sweep.csv" -f $Scale, $ImgW)
  }
  New-Item -ItemType Directory -Path (Split-Path -Parent $OutCsv) -Force | Out-Null

  $rows = @()
  foreach ($freq in $FrequenciesMhz) {
    Write-Host "===== FULL SPAN X$Scale ${ImgW}x${ImgW} @ ${freq}MHz ====="
    $status = "PASS"
    $message = ""
    try {
      & powershell -ExecutionPolicy Bypass -File scripts\run_vivado_bitstream_jtag_full_span_scale.ps1 `
        -Scale $Scale `
        -ImgW $ImgW `
        -PlFreqMhz $freq `
        -VivadoBat $VivadoBat
      if ($LASTEXITCODE -ne 0) {
        throw "Vivado flow exited with code $LASTEXITCODE"
      }
    } catch {
      $status = "FAIL"
      $message = $_.Exception.Message
      Write-Host "FREQ_SWEEP_FAIL_${freq}MHz=$message"
    }

    $freqTag = Get-FrequencyTag $freq
    $timing = Join-Path $root ("vivado\reports\jtag_full_span_x{0}_{1}x{1}{2}_timing_impl.rpt" -f $Scale, $ImgW, $freqTag)
    $util = Join-Path $root ("vivado\reports\jtag_full_span_x{0}_{1}x{1}{2}_utilization_impl.rpt" -f $Scale, $ImgW, $freqTag)
    $bit = Join-Path $root ("vivado\bitstreams\jfs_full_span_x{0}_{1}x{1}{2}.bit" -f $Scale, $ImgW, $freqTag)
    $summary = Get-TimingSummary $timing

    $rows += [pscustomobject]@{
      Scale = $Scale
      ImgW = $ImgW
      RequestedMhz = $freq
      ReportedMhz = $summary.ClockMhz
      Status = $status
      WnsNs = $summary.WnsNs
      TnsNs = $summary.TnsNs
      WhsNs = $summary.WhsNs
      TimingReport = $timing
      UtilizationReport = $util
      Bitstream = $bit
      Message = $message
    }

    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
    Write-Host "FREQ_SWEEP_CSV=$OutCsv"

    if (($status -ne "PASS") -and $StopOnFailure) {
      break
    }
  }

  $rows | Format-Table -AutoSize
}
finally {
  Pop-Location
}
