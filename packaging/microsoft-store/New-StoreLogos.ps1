# Renders Microsoft Store logo PNGs from the UScheduler icon.
# Requires Windows PowerShell 5.1 (System.Drawing). Output: packaging/microsoft-store/logos/

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot "logos"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$iconPath = Join-Path $PSScriptRoot "..\..\src\MaksIT.UScheduler.UI\Assets\icon.png"
if (-not (Test-Path -LiteralPath $iconPath)) {
  throw "Icon not found: $iconPath"
}

function New-HighQualityGraphics {
  param([System.Drawing.Image]$Image)
  $graphics = [System.Drawing.Graphics]::FromImage($Image)
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  return $graphics
}

function Save-Square {
  param([string]$Path, [int]$Size, [System.Drawing.Image]$Source)
  $bmp = New-Object System.Drawing.Bitmap $Size, $Size
  $graphics = New-HighQualityGraphics $bmp
  $graphics.DrawImage($Source, 0, 0, $Size, $Size)
  $graphics.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

function Save-Poster {
  param([string]$Path, [int]$Width, [int]$Height, [System.Drawing.Image]$Source)
  $bmp = New-Object System.Drawing.Bitmap $Width, $Height
  $graphics = New-HighQualityGraphics $bmp
  $start = New-Object System.Drawing.PointF -ArgumentList ([single]($Width * 0.2)), ([single]0)
  $end = New-Object System.Drawing.PointF -ArgumentList ([single]($Width * 0.9)), ([single]$Height)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @(
    $start,
    $end,
    ([System.Drawing.Color]::FromArgb(0x33, 0xA5, 0xCF)),
    ([System.Drawing.Color]::FromArgb(0x00, 0x2A, 0x6A))
  )
  $graphics.FillRectangle($brush, 0, 0, $Width, $Height)
  $brush.Dispose()

  $mark = [int]($Width * 0.42)
  $fontSize = [single]($Width * 0.072)
  $font = New-Object System.Drawing.Font "Segoe UI", $fontSize, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $text = "UScheduler"
  $measured = $graphics.MeasureString($text, $font)
  $gap = $Height * 0.04
  $block = $mark + $gap + $measured.Height
  $top = ($Height - $block) / 2
  $graphics.DrawImage($Source, [single](($Width - $mark) / 2), [single]$top, [single]$mark, [single]$mark)
  $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
  $format = New-Object System.Drawing.StringFormat
  $format.Alignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF 0, ([single]($top + $mark + $gap)), $Width, ($measured.Height + 8)
  $graphics.DrawString($text, $font, $white, $rect, $format)
  $format.Dispose()
  $white.Dispose()
  $font.Dispose()
  $graphics.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

$icon = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $iconPath))
try {
  Save-Square (Join-Path $outDir "box-1x1-2160x2160.png") 2160 $icon
  Save-Square (Join-Path $outDir "box-1x1-1080x1080.png") 1080 $icon
  Save-Square (Join-Path $outDir "tile-1x1-300x300.png") 300 $icon
  Save-Square (Join-Path $outDir "tile-1x1-150x150.png") 150 $icon
  Save-Square (Join-Path $outDir "tile-1x1-71x71.png") 71 $icon
  Save-Poster (Join-Path $outDir "poster-9x16-1440x2160.png") 1440 2160 $icon
  Save-Poster (Join-Path $outDir "poster-9x16-720x1080.png") 720 1080 $icon
}
finally {
  $icon.Dispose()
}

Get-ChildItem $outDir -Filter *.png | ForEach-Object {
  $img = [System.Drawing.Image]::FromFile($_.FullName)
  "{0}`t{1}x{2}`t{3:N0} KB" -f $_.Name, $img.Width, $img.Height, ($_.Length / 1KB)
  $img.Dispose()
}
