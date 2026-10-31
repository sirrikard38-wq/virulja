# Draws the app icons into web/icons: powershell -File tool/make_icons.ps1
# The mark is the temporary logo, the "Vir" spiral. Replace it here when the real
# logo is ready and run this again.
Add-Type -AssemblyName System.Drawing

$out = Join-Path $PSScriptRoot '..\web\icons'
New-Item -ItemType Directory -Force $out | Out-Null

function Save-Icon([string]$name, [int]$size, [double]$markScale) {
  $bitmap = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bitmap)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::FromArgb(79, 87, 48))

  # The spiral is made of half circles in a 64 x 64 drawing, as in the logo.
  $unit = $size * $markScale / 48.0
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(247, 245, 240)), ([single]($unit * 4))
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $cx = $size / 2.0
  $cy = $size / 2.0
  $x = 0.0
  $top = $true
  foreach ($r in 4, 8, 12, 16, 20, 24) {
    # Each half circle starts where the last one ended.
    $step = if ($top) { 1 } else { -1 }
    $centre = $x + $step * $r
    $rect = New-Object System.Drawing.RectangleF ([single]($cx + ($centre - $r) * $unit)), ([single]($cy - $r * $unit)), ([single](2 * $r * $unit)), ([single](2 * $r * $unit))
    $start = if ($top) { 180 } else { 0 }
    $g.DrawArc($pen, $rect, $start, 180)
    $x = $x + 2 * $step * $r
    $top = -not $top
  }
  $bitmap.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $pen.Dispose()
  $g.Dispose()
  $bitmap.Dispose()
}

Save-Icon 'favicon-32.png' 32 0.8
Save-Icon 'apple-touch-icon.png' 180 0.68
Save-Icon 'icon-192.png' 192 0.68
Save-Icon 'icon-512.png' 512 0.68
Save-Icon 'icon-maskable-512.png' 512 0.52
