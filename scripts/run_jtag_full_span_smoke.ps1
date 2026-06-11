param(
  [ValidateSet(2, 4)]
  [int]$Scale = 4,
  [ValidateRange(1, 16)]
  [int]$ImgW = 1,
  [ValidatePattern("^[0-9A-Fa-f]{6}$")]
  [string]$PixelHex = "406080",
  [string]$VivadoBat = "D:\software\2025.2\Vivado\bin\vivado.bat",
  [string]$Bitstream = "",
  [string]$Base = "0xA0000000",
  [string]$OutputDir = "board_runs\full_span_jtag_smoke",
  [string]$InputPng = "",
  [string]$InputRaw = "",
  [string]$OutputRaw = "",
  [string]$OutputPng = "",
  [switch]$NoProgram,
  [switch]$SkipHardware
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  if ($Bitstream -eq "") {
    $Bitstream = Join-Path $root ("vivado\bitstreams\jfs_full_span_x{0}_{1}x{1}.bit" -f $Scale, $ImgW)
  }

  $outDirAbs = Join-Path $root $OutputDir
  New-Item -ItemType Directory -Path $outDirAbs -Force | Out-Null

  $tag = "x{0}_{1}x{1}" -f $Scale, $ImgW
  $inputRawPath = Join-Path $outDirAbs ("input_{0}.rgb" -f $tag)
  if ($InputRaw -ne "") {
    $inputRawPath = $InputRaw
  }

  $outputRawPath = Join-Path $outDirAbs ("output_{0}.rgb" -f $tag)
  if ($OutputRaw -ne "") {
    $outputRawPath = $OutputRaw
  }

  $outputPpm = Join-Path $outDirAbs ("output_{0}.ppm" -f $tag)
  if ($OutputPng -eq "") {
    $OutputPng = Join-Path $outDirAbs ("output_{0}.png" -f $tag)
  }

  $vivadoLog = Join-Path $outDirAbs ("vivado_jtag_{0}.log" -f $tag)
  $vivadoJournal = Join-Path $outDirAbs ("vivado_jtag_{0}.jou" -f $tag)

  if ($InputPng -ne "") {
    python tools\convert_rgb_raw.py to-raw $InputPng $inputRawPath --width $ImgW --height $ImgW
  } elseif ($InputRaw -ne "") {
    if (-not (Test-Path $inputRawPath)) {
      throw "Input raw not found: $inputRawPath"
    }
    $existingInputBytes = [System.IO.File]::ReadAllBytes($inputRawPath)
    $expectedInputBytes = 3 * $ImgW * $ImgW
    if ($existingInputBytes.Length -ne $expectedInputBytes) {
      throw "Input raw size mismatch: got $($existingInputBytes.Length), expected $expectedInputBytes"
    }
  } else {
    $r = [Convert]::ToByte($PixelHex.Substring(0, 2), 16)
    $g = [Convert]::ToByte($PixelHex.Substring(2, 2), 16)
    $b = [Convert]::ToByte($PixelHex.Substring(4, 2), 16)

    [byte[]]$inputBytes = New-Object byte[] (3 * $ImgW * $ImgW)
    for ($y = 0; $y -lt $ImgW; $y++) {
      for ($x = 0; $x -lt $ImgW; $x++) {
        $idx = 3 * ($y * $ImgW + $x)
        # Deterministic color tile for default smoke tests.
        $inputBytes[$idx + 0] = [byte](($r + 32 * $x) -band 0xff)
        $inputBytes[$idx + 1] = [byte](($g + 32 * $y) -band 0xff)
        $inputBytes[$idx + 2] = [byte](($b + 16 * ($x + $y)) -band 0xff)
      }
    }
    [System.IO.File]::WriteAllBytes($inputRawPath, $inputBytes)
  }

  Write-Host "FULL_SPAN_JTAG_SMOKE_SCALE=$Scale"
  Write-Host "FULL_SPAN_JTAG_SMOKE_IMG_W=$ImgW"
  Write-Host "FULL_SPAN_JTAG_INPUT=$inputRawPath"
  Write-Host "FULL_SPAN_JTAG_OUTPUT_RAW=$outputRawPath"
  Write-Host "FULL_SPAN_JTAG_OUTPUT_PPM=$outputPpm"
  Write-Host "FULL_SPAN_JTAG_OUTPUT_PNG=$OutputPng"
  Write-Host "FULL_SPAN_JTAG_VIVADO_LOG=$vivadoLog"
  Write-Host "FULL_SPAN_JTAG_PIXEL_HEX=$PixelHex"

  if ($SkipHardware) {
    Write-Host "SKIP_HARDWARE=1"
    return
  }

  if (-not $NoProgram) {
    if (-not (Test-Path $Bitstream)) {
      throw "Bitstream not found: $Bitstream"
    }
    Write-Host "FULL_SPAN_JTAG_BITSTREAM=$Bitstream"
  } else {
    Write-Host "FULL_SPAN_JTAG_BITSTREAM=already_programmed"
  }

  $tcl = Join-Path $root "scripts\jtag_rgb_transfer.tcl"
  $args = @(
    "-mode", "batch",
    "-log", $vivadoLog,
    "-journal", $vivadoJournal,
    "-source", $tcl,
    "-tclargs",
    "--input", $inputRawPath,
    "--output", $outputRawPath,
    "--width", [string]$ImgW,
    "--height", [string]$ImgW,
    "--scale", [string]$Scale,
    "--base", $Base
  )
  if (-not $NoProgram) {
    $args += @("--bitstream", $Bitstream)
  }

  & $VivadoBat @args
  if ($LASTEXITCODE -ne 0) {
    throw "Vivado JTAG transfer failed with exit code $LASTEXITCODE"
  }

  $expectedBytes = 3 * $ImgW * $ImgW * $Scale * $Scale
  if (-not (Test-Path $outputRawPath)) {
    throw "Output raw file was not generated: $outputRawPath"
  }
  $outputBytes = [System.IO.File]::ReadAllBytes($outputRawPath)
  if ($outputBytes.Length -ne $expectedBytes) {
    throw "Output raw size mismatch: got $($outputBytes.Length), expected $expectedBytes"
  }

  $outW = $ImgW * $Scale
  $outH = $ImgW * $Scale
  $header = [System.Text.Encoding]::ASCII.GetBytes("P6`n$outW $outH`n255`n")
  [byte[]]$ppmBytes = New-Object byte[] ($header.Length + $outputBytes.Length)
  [Array]::Copy($header, 0, $ppmBytes, 0, $header.Length)
  [Array]::Copy($outputBytes, 0, $ppmBytes, $header.Length, $outputBytes.Length)
  [System.IO.File]::WriteAllBytes($outputPpm, $ppmBytes)
  python tools\convert_rgb_raw.py from-raw $outputRawPath $OutputPng --width $outW --height $outH

  $compareDir = Join-Path $OutputDir ("compare_{0}" -f $tag)
  powershell -ExecutionPolicy Bypass -File scripts\compare_jtag_full_span_output.ps1 `
    -Scale $Scale `
    -ImgW $ImgW `
    -InputRaw $inputRawPath `
    -OutputRaw $outputRawPath `
    -BuildDir $compareDir

  Write-Host "FULL_SPAN_JTAG_OUTPUT_BYTES=$($outputBytes.Length)"
  Write-Host "FULL_SPAN_JTAG_OUTPUT_IMAGE=$OutputPng"
  Write-Host "FULL_SPAN_JTAG_COMPARE_DIR=$compareDir"
  Write-Host "FULL_SPAN_JTAG_SMOKE_PASS=1"
}
finally {
  Pop-Location
}
