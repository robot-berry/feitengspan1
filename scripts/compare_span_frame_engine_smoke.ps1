param(
    [int]$ImgW = 1,
    [string]$PreviewPng = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Vivado = "D:\software\2025.2\Vivado\bin\vivado.bat"
$RefRgb = Join-Path $Root ("build\span_fixed_ref_{0}x{0}.rgb" -f $ImgW)
$RefPng = Join-Path $Root ("build\span_fixed_ref_{0}x{0}.png" -f $ImgW)
$RtlRgbSrc = Join-Path $Root "build\vivado_span_frame_engine_smoke\span_frame_engine_smoke.sim\sim_1\behav\xsim\span_frame_engine_smoke_out.rgb"
$RtlRgb = Join-Path $Root ("build\span_rtl_smoke_{0}x{0}.rgb" -f $ImgW)
$RtlPng = Join-Path $Root ("build\span_rtl_smoke_{0}x{0}.png" -f $ImgW)
$InputRgb = Join-Path $Root ("build\span_smoke_input_{0}x{0}.rgb" -f $ImgW)
$Config = Join-Path $Root "rtl\generated\official_span_model_config.vh"

Push-Location $Root
try {
    $configText = Get-Content $Config -Raw
    if ($configText -notmatch "OFFICIAL_SPAN_MODEL_SCALE\s+([24])") {
        throw "Cannot determine OFFICIAL_SPAN_MODEL_SCALE from $Config"
    }
    $scale = [int]$Matches[1]
    $Manifest = Join-Path $Root ("rtl\generated\official_span_x{0}\official_span_manifest.json" -f $scale)
    if ($PreviewPng -eq "") {
        $PreviewPng = Join-Path $Root ("build\span_validation_preview_x{0}_{1}x{1}.png" -f $scale, $ImgW)
    }

    [byte[]]$inputBytes = New-Object byte[] (3 * $ImgW * $ImgW)
    for ($i = 0; $i -lt ($ImgW * $ImgW); $i++) {
        $idx = 3 * $i
        $inputBytes[$idx + 0] = 0x40
        $inputBytes[$idx + 1] = 0x60
        $inputBytes[$idx + 2] = 0x80
    }
    [System.IO.File]::WriteAllBytes($InputRgb, $inputBytes)

    python tools\span_official_fixed_ref.py `
        --manifest $Manifest `
        --width $ImgW `
        --height $ImgW `
        --out-rgb $RefRgb `
        --out-png $RefPng

    $env:SPAN_FRAME_ENGINE_SMOKE_IMG_W = [string]$ImgW
    & $Vivado -mode batch -source scripts\run_vivado_sim_span_frame_engine_smoke.tcl

    if (!(Test-Path $RtlRgbSrc)) {
        throw "RTL output file was not generated: $RtlRgbSrc"
    }
    Copy-Item $RtlRgbSrc $RtlRgb -Force

    $outW = $ImgW * $scale
    $outH = $ImgW * $scale
    python tools\convert_rgb_raw.py from-raw $RtlRgb $RtlPng --width $outW --height $outH
    python tools\make_sr_validation_preview.py `
        --input $InputRgb `
        --input-width $ImgW `
        --input-height $ImgW `
        --ref $RefPng `
        --actual $RtlPng `
        --actual-label "RTL" `
        --out $PreviewPng `
        --title "RTL SPAN x${scale} ${ImgW}x${ImgW}"

    $ref = [System.IO.File]::ReadAllBytes($RefRgb)
    $rtl = [System.IO.File]::ReadAllBytes($RtlRgb)
    if ($ref.Length -ne $rtl.Length) {
        throw "Length mismatch: ref=$($ref.Length), rtl=$($rtl.Length)"
    }

    $mismatch = 0
    for ($i = 0; $i -lt $ref.Length; $i++) {
        if ($ref[$i] -ne $rtl[$i]) {
            $mismatch++
            if ($mismatch -le 16) {
                Write-Host ("Mismatch byte {0}: ref=0x{1:X2}, rtl=0x{2:X2}" -f $i, $ref[$i], $rtl[$i])
            }
        }
    }

    if ($mismatch -ne 0) {
        throw "SPAN frame engine mismatch count: $mismatch"
    }

    Write-Host "PASS compare_span_frame_engine_smoke_x${scale}_${ImgW}x${ImgW}: $($ref.Length) bytes match"
    Write-Host "RTL_PNG=$RtlPng"
    Write-Host "PREVIEW_PNG=$PreviewPng"
}
finally {
    Remove-Item Env:\SPAN_FRAME_ENGINE_SMOKE_IMG_W -ErrorAction SilentlyContinue
    Pop-Location
}
