param(
  [ValidateSet(2, 4)]
  [int]$Scale = 4,
  [ValidateRange(1, 16)]
  [int]$ImgW = 4,
  [string]$InputRaw = "",
  [string]$OutputRaw = "",
  [string]$BuildDir = "build",
  [string]$PreviewPng = ""
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  $tag = "x{0}_{1}x{1}" -f $Scale, $ImgW
  if ($InputRaw -eq "") {
    $InputRaw = Join-Path $root ("board_runs\full_span_jtag_smoke\input_{0}.rgb" -f $tag)
  }
  if ($OutputRaw -eq "") {
    $OutputRaw = Join-Path $root ("board_runs\full_span_jtag_smoke\output_{0}.rgb" -f $tag)
  }

  if (-not (Test-Path $InputRaw)) {
    throw "Input raw not found: $InputRaw"
  }
  if (-not (Test-Path $OutputRaw)) {
    throw "Output raw not found: $OutputRaw"
  }

  $manifest = Join-Path $root ("rtl\generated\official_span_x{0}\official_span_manifest.json" -f $Scale)
  if (-not (Test-Path $manifest)) {
    throw "Manifest not found: $manifest"
  }

  $buildAbs = Join-Path $root $BuildDir
  New-Item -ItemType Directory -Path $buildAbs -Force | Out-Null

  $inputPng = Join-Path $buildAbs ("jtag_input_{0}.png" -f $tag)
  $refRgb = Join-Path $buildAbs ("span_fixed_ref_jtag_{0}.rgb" -f $tag)
  $refPng = Join-Path $buildAbs ("span_fixed_ref_jtag_{0}.png" -f $tag)
  $boardPng = Join-Path $buildAbs ("jtag_board_{0}.png" -f $tag)
  if ($PreviewPng -eq "") {
    $PreviewPng = Join-Path $buildAbs ("validation_preview_{0}.png" -f $tag)
  }

  python tools\convert_rgb_raw.py from-raw $InputRaw $inputPng --width $ImgW --height $ImgW
  python tools\span_official_fixed_ref.py `
    --manifest $manifest `
    --width $ImgW `
    --height $ImgW `
    --input-png $inputPng `
    --out-rgb $refRgb `
    --out-png $refPng

  $outW = $ImgW * $Scale
  $outH = $ImgW * $Scale
  python tools\convert_rgb_raw.py from-raw $OutputRaw $boardPng --width $outW --height $outH
  python tools\make_sr_validation_preview.py `
    --input $InputRaw `
    --input-width $ImgW `
    --input-height $ImgW `
    --ref $refPng `
    --actual $boardPng `
    --actual-label "Board" `
    --out $PreviewPng `
    --title "JTAG SPAN x${Scale} ${ImgW}x${ImgW}"

  [byte[]]$board = [System.IO.File]::ReadAllBytes($OutputRaw)
  [byte[]]$ref = [System.IO.File]::ReadAllBytes($refRgb)
  if ($board.Length -ne $ref.Length) {
    throw "Length mismatch: board=$($board.Length), ref=$($ref.Length)"
  }

  $mismatch = 0
  for ($i = 0; $i -lt $board.Length; $i++) {
    if ($board[$i] -ne $ref[$i]) {
      $mismatch++
      if ($mismatch -le 16) {
        Write-Host ("Mismatch byte {0}: board=0x{1:X2}, ref=0x{2:X2}" -f $i, $board[$i], $ref[$i])
      }
    }
  }

  if ($mismatch -ne 0) {
    throw "JTAG full SPAN output mismatch count: $mismatch"
  }

  Write-Host "PASS compare_jtag_full_span_output_x${Scale}_${ImgW}x${ImgW}: $($board.Length) bytes match"
  Write-Host "REF_RGB=$refRgb"
  Write-Host "REF_PNG=$refPng"
  Write-Host "BOARD_PNG=$boardPng"
  Write-Host "PREVIEW_PNG=$PreviewPng"
}
finally {
  Pop-Location
}
