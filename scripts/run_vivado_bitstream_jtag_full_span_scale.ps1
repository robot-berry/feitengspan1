param(
  [ValidateSet(2, 4)]
  [int]$Scale = 2,
  [int]$ImgW = 1,
  [ValidateRange(1, 300)]
  [int]$PlFreqMhz = 25,
  [string]$VivadoBat = "D:\software\2025.2\Vivado\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  if ($Scale -eq 2) {
    powershell -ExecutionPolicy Bypass -File scripts\export_official_span_x2_to_rtl.ps1
  } else {
    powershell -ExecutionPolicy Bypass -File scripts\export_official_span_x4_to_rtl.ps1
  }

  $env:JTAG_FULL_SPAN_IMG_W = [string]$ImgW
  $env:JTAG_FULL_SPAN_SCALE = [string]$Scale
  $env:JTAG_FULL_SPAN_PL_FREQ_MHZ = [string]$PlFreqMhz
  & $VivadoBat -mode batch -source scripts\run_vivado_bitstream_jtag_full_span.tcl
  if ($LASTEXITCODE -ne 0) {
    throw "Vivado bitstream flow failed with exit code $LASTEXITCODE"
  }

  $bitDir = Join-Path $root "vivado\bitstreams"
  New-Item -ItemType Directory -Path $bitDir -Force | Out-Null
  $srcBit = Join-Path $root "vivado\jfs\jfs.runs\impl_1\jfs_wrapper.bit"
  $freqTag = if ($PlFreqMhz -eq 25) { "" } else { "_f${PlFreqMhz}m" }
  $dstBit = Join-Path $bitDir ("jfs_full_span_x{0}_{1}x{1}{2}.bit" -f $Scale, $ImgW, $freqTag)
  Copy-Item -LiteralPath $srcBit -Destination $dstBit -Force

  $reportDir = Join-Path $root "vivado\reports"
  New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
  $srcUtil = Join-Path $root "vivado\jfs\reports\jtag_full_span_utilization_impl.rpt"
  $srcTiming = Join-Path $root "vivado\jfs\reports\jtag_full_span_timing_impl.rpt"
  $dstUtil = Join-Path $reportDir ("jtag_full_span_x{0}_{1}x{1}{2}_utilization_impl.rpt" -f $Scale, $ImgW, $freqTag)
  $dstTiming = Join-Path $reportDir ("jtag_full_span_x{0}_{1}x{1}{2}_timing_impl.rpt" -f $Scale, $ImgW, $freqTag)
  Copy-Item -LiteralPath $srcUtil -Destination $dstUtil -Force
  Copy-Item -LiteralPath $srcTiming -Destination $dstTiming -Force

  Write-Host "FULL_SPAN_SCALE=$Scale"
  Write-Host "FULL_SPAN_IMG_W=$ImgW"
  Write-Host "FULL_SPAN_PL_FREQ_MHZ=$PlFreqMhz"
  Write-Host "FULL_SPAN_BIT=$dstBit"
  Write-Host "FULL_SPAN_UTIL=$dstUtil"
  Write-Host "FULL_SPAN_TIMING=$dstTiming"
}
finally {
  Remove-Item Env:\JTAG_FULL_SPAN_IMG_W -ErrorAction SilentlyContinue
  Remove-Item Env:\JTAG_FULL_SPAN_SCALE -ErrorAction SilentlyContinue
  Remove-Item Env:\JTAG_FULL_SPAN_PL_FREQ_MHZ -ErrorAction SilentlyContinue
  Pop-Location
}
