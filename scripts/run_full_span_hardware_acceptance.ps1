param(
  [ValidateSet(2, 4)]
  [int]$Scale = 4,
  [ValidateRange(1, 32)]
  [int]$ImgW = 32,
  [ValidateRange(1, 300)]
  [int]$PlFreqMhz = 25,
  [string]$InputPng = "external\SPAN\test_scripts\data\baboon.png",
  [string]$VivadoBat = "D:\software\2025.2\Vivado\bin\vivado.bat",
  [string]$OutputDir = "",
  [switch]$SkipBuild,
  [switch]$SkipJtag,
  [switch]$NoProgram,
  [switch]$DryRun,
  [switch]$SummarizeExisting
)

$ErrorActionPreference = "Stop"

function Get-FirstRegexValue {
  param(
    [string]$Path,
    [string]$Pattern,
    [int]$Group = 1
  )
  if (-not (Test-Path $Path)) {
    return $null
  }
  $match = Select-String -Path $Path -Pattern $Pattern | Select-Object -First 1
  if ($null -eq $match) {
    return $null
  }
  return $match.Matches[0].Groups[$Group].Value
}

function Get-TimingSummary {
  param([string]$Path)
  $wns = $null
  $whs = $null
  if (Test-Path $Path) {
    foreach ($line in Get-Content -Path $Path) {
      if ($line -match "^\s*([-+]?[0-9]+(?:\.[0-9]+)?)\s+[-+]?[0-9]+(?:\.[0-9]+)?\s+\d+\s+\d+\s+([-+]?[0-9]+(?:\.[0-9]+)?)\s+") {
        $wns = $Matches[1]
        $whs = $Matches[2]
        break
      }
    }
  }
  [ordered]@{
    path = $Path
    exists = [bool](Test-Path $Path)
    wns_ns = $wns
    whs_ns = $whs
    timing_met = if (Test-Path $Path) { [bool](Select-String -Path $Path -Pattern "All user specified timing constraints are met" -Quiet) } else { $false }
  }
}

function Get-UtilValue {
  param(
    [string]$Path,
    [string]$Name
  )
  if (-not (Test-Path $Path)) {
    return $null
  }
  $escaped = [regex]::Escape($Name)
  $match = Select-String -Path $Path -Pattern "\|\s*$escaped\s*\|\s*([0-9]+(?:\.[0-9]+)?)\s*\|" | Select-Object -First 1
  if ($null -eq $match) {
    return $null
  }
  return $match.Matches[0].Groups[1].Value
}

function Get-UtilSummary {
  param([string]$Path)
  [ordered]@{
    path = $Path
    exists = [bool](Test-Path $Path)
    clb_luts = Get-UtilValue -Path $Path -Name "CLB LUTs"
    clb_registers = Get-UtilValue -Path $Path -Name "CLB Registers"
    block_ram_tile = Get-UtilValue -Path $Path -Name "Block RAM Tile"
    dsps = Get-UtilValue -Path $Path -Name "DSPs"
  }
}

function Compare-RawBytes {
  param(
    [string]$ActualPath,
    [string]$ReferencePath
  )
  if (-not (Test-Path $ActualPath) -or -not (Test-Path $ReferencePath)) {
    return [ordered]@{
      available = $false
      actual_bytes = 0
      reference_bytes = 0
      mismatch_bytes = $null
      match = $false
    }
  }
  [byte[]]$actual = [System.IO.File]::ReadAllBytes($ActualPath)
  [byte[]]$reference = [System.IO.File]::ReadAllBytes($ReferencePath)
  $mismatch = 0
  $limit = [Math]::Min($actual.Length, $reference.Length)
  for ($i = 0; $i -lt $limit; $i++) {
    if ($actual[$i] -ne $reference[$i]) {
      $mismatch++
    }
  }
  $mismatch += [Math]::Abs($actual.Length - $reference.Length)
  return [ordered]@{
    available = $true
    actual_bytes = $actual.Length
    reference_bytes = $reference.Length
    mismatch_bytes = $mismatch
    match = [bool]($mismatch -eq 0)
  }
}

function Write-MarkdownSummary {
  param(
    [string]$Path,
    [hashtable]$Summary
  )
  $status = if ($Summary.passed) { "PASS" } else { "FAIL" }
  $lines = @(
    "# Full SPAN hardware acceptance",
    "",
    "Result: ``$status``",
    "",
    "Target: X$($Summary.scale) ``$($Summary.img_w)x$($Summary.img_w) -> $($Summary.output_w)x$($Summary.output_h)``",
    "PL frequency: ``$($Summary.pl_freq_mhz) MHz``",
    "Input PNG: ``$($Summary.input_png)``",
    "",
    "## Artifacts",
    "",
    "- bitstream: ``$($Summary.bitstream)``",
    "- timing report: ``$($Summary.timing.path)``",
    "- utilization report: ``$($Summary.utilization.path)``",
    "- board output PNG: ``$($Summary.jtag.output_png)``",
    "- comparison preview: ``$($Summary.jtag.preview_png)``",
    "",
    "## Checks",
    "",
    "| Check | Result | Value |",
    "| --- | --- | --- |",
    "| dry run | ``$($Summary.dry_run)`` | - |",
    "| bitstream exists | ``$($Summary.checks.bitstream_exists)`` | ``$($Summary.bitstream)`` |",
    "| timing met | ``$($Summary.checks.timing_met)`` | WNS ``$($Summary.timing.wns_ns)`` ns, WHS ``$($Summary.timing.whs_ns)`` ns |",
    "| JTAG ran | ``$($Summary.checks.jtag_ran)`` | output bytes ``$($Summary.jtag.output_bytes)`` |",
    "| raw reference match | ``$($Summary.checks.reference_match)`` | mismatch bytes ``$($Summary.jtag.compare.mismatch_bytes)`` |",
    "| comparison preview exists | ``$($Summary.checks.preview_exists)`` | ``$($Summary.jtag.preview_png)`` |",
    "",
    "## Resources",
    "",
    "- CLB LUTs: ``$($Summary.utilization.clb_luts)``",
    "- CLB Registers: ``$($Summary.utilization.clb_registers)``",
    "- Block RAM Tile: ``$($Summary.utilization.block_ram_tile)``",
    "- DSPs: ``$($Summary.utilization.dsps)``",
    ""
  )
  Set-Content -Path $Path -Value $lines -Encoding UTF8
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  $tag = "x{0}_{1}x{1}" -f $Scale, $ImgW
  if ($OutputDir -eq "") {
    $OutputDir = "board_runs\hardware_acceptance\full_span_$tag"
  }
  $outDirAbs = Join-Path $root $OutputDir
  New-Item -ItemType Directory -Path $outDirAbs -Force | Out-Null

  $freqTag = if ($PlFreqMhz -eq 25) { "" } else { "_f${PlFreqMhz}m" }
  $bitstream = Join-Path $root ("vivado\bitstreams\jfs_full_span_x{0}_{1}x{1}{2}.bit" -f $Scale, $ImgW, $freqTag)
  $timingReport = Join-Path $root ("vivado\reports\jtag_full_span_x{0}_{1}x{1}{2}_timing_impl.rpt" -f $Scale, $ImgW, $freqTag)
  $utilReport = Join-Path $root ("vivado\reports\jtag_full_span_x{0}_{1}x{1}{2}_utilization_impl.rpt" -f $Scale, $ImgW, $freqTag)
  $jtagDir = Join-Path $OutputDir "jtag"
  $outputRaw = Join-Path $outDirAbs ("board_output_$tag.rgb")
  $outputPng = Join-Path $outDirAbs ("board_output_$tag.png")
  $previewPng = Join-Path $root (Join-Path $jtagDir ("compare_$tag\validation_preview_$tag.png"))
  $summaryJson = Join-Path $outDirAbs "summary.json"
  $summaryMd = Join-Path $outDirAbs "summary.md"

  $plannedBuild = "powershell -ExecutionPolicy Bypass -File scripts\run_vivado_bitstream_jtag_full_span_scale.ps1 -Scale $Scale -ImgW $ImgW -PlFreqMhz $PlFreqMhz -VivadoBat `"$VivadoBat`""
  $plannedJtag = "powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale $Scale -ImgW $ImgW -InputPng `"$InputPng`" -Bitstream `"$bitstream`" -OutputDir `"$jtagDir`" -OutputRaw `"$outputRaw`" -OutputPng `"$outputPng`""
  if ($NoProgram) {
    $plannedJtag += " -NoProgram"
  }

  if ($DryRun) {
    Write-Host "DRY_RUN=1"
    Write-Host "PLAN_BUILD=$plannedBuild"
    Write-Host "PLAN_JTAG=$plannedJtag"
    Write-Host "VIVADO_BAT_EXISTS=$([bool](Test-Path $VivadoBat))"
    Write-Host "INPUT_PNG_EXISTS=$([bool](Test-Path $InputPng))"
    Write-Host "BITSTREAM_EXISTS=$([bool](Test-Path $bitstream))"
  } elseif ($SummarizeExisting) {
    Write-Host "SUMMARIZE_EXISTING=1"
    Write-Host "BITSTREAM=$bitstream"
    Write-Host "OUTPUT_RAW=$outputRaw"
  } else {
    if (-not $SkipBuild) {
      Write-Host "RUN_BUILD=$plannedBuild"
      powershell -ExecutionPolicy Bypass -File scripts\run_vivado_bitstream_jtag_full_span_scale.ps1 `
        -Scale $Scale `
        -ImgW $ImgW `
        -PlFreqMhz $PlFreqMhz `
        -VivadoBat $VivadoBat
    }

    if (-not $SkipJtag) {
      Write-Host "RUN_JTAG=$plannedJtag"
      $jtagArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run_jtag_full_span_smoke.ps1",
        "-Scale", [string]$Scale,
        "-ImgW", [string]$ImgW,
        "-InputPng", $InputPng,
        "-Bitstream", $bitstream,
        "-OutputDir", $jtagDir,
        "-OutputRaw", $outputRaw,
        "-OutputPng", $outputPng
      )
      if ($NoProgram) {
        $jtagArgs += "-NoProgram"
      }
      powershell @jtagArgs
    }
  }

  $expectedOutputBytes = 3 * $ImgW * $ImgW * $Scale * $Scale
  $actualOutputBytes = if (Test-Path $outputRaw) { (Get-Item $outputRaw).Length } else { 0 }
  $refRgb = Join-Path $root (Join-Path $jtagDir ("compare_$tag\span_fixed_ref_jtag_$tag.rgb"))
  $rawCompare = Compare-RawBytes -ActualPath $outputRaw -ReferencePath $refRgb
  $timing = Get-TimingSummary -Path $timingReport
  $util = Get-UtilSummary -Path $utilReport
  $checks = [ordered]@{
    vivado_bat_exists = [bool](Test-Path $VivadoBat)
    input_png_exists = [bool](Test-Path $InputPng)
    bitstream_exists = [bool](Test-Path $bitstream)
    timing_met = [bool]$timing.timing_met
    jtag_ran = [bool]((Test-Path $outputRaw) -and ($actualOutputBytes -eq $expectedOutputBytes))
    reference_match = [bool]$rawCompare.match
    preview_exists = [bool](Test-Path $previewPng)
  }
  $passed = if ($DryRun) {
    $checks.vivado_bat_exists -and $checks.input_png_exists
  } elseif ($SummarizeExisting) {
    $checks.bitstream_exists -and $checks.timing_met -and $checks.jtag_ran -and $checks.reference_match -and $checks.preview_exists
  } elseif ($SkipJtag) {
    $checks.bitstream_exists -and $checks.timing_met
  } else {
    $checks.bitstream_exists -and $checks.timing_met -and $checks.jtag_ran -and $checks.reference_match -and $checks.preview_exists
  }

  $summary = [ordered]@{
    passed = [bool]$passed
    dry_run = [bool]$DryRun
    branch = (git branch --show-current)
    scale = $Scale
    img_w = $ImgW
    output_w = $ImgW * $Scale
    output_h = $ImgW * $Scale
    pl_freq_mhz = $PlFreqMhz
    input_png = $InputPng
    vivado_bat = $VivadoBat
    bitstream = $bitstream
    timing = $timing
    utilization = $util
    jtag = [ordered]@{
      output_raw = $outputRaw
      output_png = $outputPng
      output_bytes = $actualOutputBytes
      expected_output_bytes = $expectedOutputBytes
      reference_raw = $refRgb
      compare = $rawCompare
      preview_png = $previewPng
      output_dir = $jtagDir
    }
    checks = $checks
    planned_commands = [ordered]@{
      build = $plannedBuild
      jtag = $plannedJtag
    }
  }

  $summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryJson -Encoding UTF8
  Write-MarkdownSummary -Path $summaryMd -Summary $summary

  Write-Host "FULL_SPAN_HW_ACCEPTANCE_SUMMARY_JSON=$summaryJson"
  Write-Host "FULL_SPAN_HW_ACCEPTANCE_SUMMARY_MD=$summaryMd"
  Write-Host "FULL_SPAN_HW_ACCEPTANCE_PASS=$([int]$passed)"
  if (-not $passed) {
    throw "Full SPAN hardware acceptance failed"
  }
}
finally {
  Pop-Location
}
