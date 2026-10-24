# Launches deckle.exe on the CI desktop over a page of text, fails unless the
# tray window and a visible overlay appear and the overlay changes the screen,
# and saves screenshots of a few papers and the tray menu for review.
#
#   pwsh windows/scripts/smoke.ps1 -Exe windows/target/release/deckle.exe -OutDir screenshots

param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Native {
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr target, int x, int y, int width, int height,
        IntPtr source, int sourceX, int sourceY, uint operation);
    const uint SRCCOPY = 0x00CC0020;
    // Includes layered windows, and the overlay is one. Graphics.CopyFromScreen
    // refuses this flag combination.
    const uint CAPTUREBLT = 0x40000000;

    // Copies a screen rectangle into the device context `target`.
    public static void CopyScreen(IntPtr target, int x, int y, int width, int height) {
        IntPtr screen = GetDC(IntPtr.Zero);
        try {
            if (!BitBlt(target, 0, 0, width, height, screen, x, y, SRCCOPY | CAPTUREBLT)) {
                throw new InvalidOperationException("BitBlt from the screen failed");
            }
        } finally {
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowW(string className, string title);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@
[Native]::SetProcessDPIAware() | Out-Null

$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$work = Join-Path ([System.IO.Path]::GetTempPath()) "deckle-smoke-$PID"
# Deckle keeps its settings under %APPDATA%; point it at a scratch folder.
$env:APPDATA = Join-Path $work 'appdata'
New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'Deckle') | Out-Null
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

function Save-Screen([string] $Name) {
    $bitmap = [System.Drawing.Bitmap]::new($screen.Width, $screen.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    try {
        [Native]::CopyScreen($hdc, $screen.X, $screen.Y, $screen.Width, $screen.Height)
    } finally {
        $graphics.ReleaseHdc($hdc)
        $graphics.Dispose()
    }
    $path = Join-Path $OutDir "$Name.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Host "Saved $path"
    $path
}

# Mean brightness of a block in the middle of the screen.
function Get-Brightness([string] $Path) {
    $bitmap = [System.Drawing.Bitmap]::new($Path)
    $total = 0.0
    $x0 = [int]($screen.Width / 2) - 40
    $y0 = [int]($screen.Height / 2) - 40
    for ($y = $y0; $y -lt $y0 + 80; $y += 2) {
        for ($x = $x0; $x -lt $x0 + 80; $x += 2) {
            $total += $bitmap.GetPixel($x, $y).GetBrightness()
        }
    }
    $bitmap.Dispose()
    $total / 1600
}

function Wait-Window([string] $Class, [bool] $MustBeVisible) {
    for ($i = 0; $i -lt 50; $i++) {
        # [NullString]: PowerShell would pass $null as "", which only
        # matches windows with an empty title.
        $hwnd = [Native]::FindWindowW($Class, [NullString]::Value)
        if ($hwnd -ne [IntPtr]::Zero -and (-not $MustBeVisible -or [Native]::IsWindowVisible($hwnd))) {
            return $hwnd
        }
        Start-Sleep -Milliseconds 200
    }
    throw "Deckle never created a $(if ($MustBeVisible) { 'visible ' })$Class window"
}

function Start-Deckle([string] $Paper, [double] $Intensity) {
    $value = $Intensity.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    Set-Content -Path (Join-Path $env:APPDATA 'Deckle\settings.ini') -Value "enabled=true`nintensity=$value`npaper=$Paper"
    $process = Start-Process -FilePath $Exe -PassThru
    $tray = Wait-Window 'DeckleTray' $false
    Wait-Window 'DeckleOverlay' $true | Out-Null
    Start-Sleep -Milliseconds 800
    if ($process.HasExited) { throw "deckle.exe exited with code $($process.ExitCode)" }
    @{ Process = $process; Tray = $tray }
}

function Stop-Deckle($Deckle) {
    Stop-Process -Id $Deckle.Process.Id -Force
    $Deckle.Process.WaitForExit()
}

# Something to read under the paper.
$sample = Join-Path $work 'Reading sample.txt'
Set-Content -Path $sample -Value @'
Deckle lays a subtle paper-grain texture over the whole screen, so long reading
and writing sessions feel more like paper than glass.

A deckle is the wooden frame used in hand papermaking. It leaves behind the soft,
feathered "deckle edge" that marks real handmade paper.

The overlay is click-through: every pixel of your work stays interactive. Choose a
smooth dimming veil or a textured finish from the tray menu, set the intensity,
and toggle the paper from anywhere with Ctrl+Alt+P.

Quiet reading papers keep pattern variation low; textured papers add tooth, weave,
and fibers. Every paper is rendered from a deterministic recipe, so it looks the
same on every launch and on every monitor.
'@
try {
    $notepad = Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$sample`"" -WindowStyle Maximized -PassThru
    Start-Sleep -Seconds 3
} catch {
    # The paper still shows over the bare desktop.
    Write-Host "Could not open Notepad: $_"
    $notepad = $null
}

try {
    $bare = Get-Brightness (Save-Screen 'bare')

    foreach ($paper in 'classic-matte', 'sunbaked-parchment', 'linen-veil', 'carbon-ledger') {
        $deckle = Start-Deckle $paper 0.35
        try {
            $covered = Get-Brightness (Save-Screen $paper)
            Write-Host ("{0}: brightness {1:N3} without paper, {2:N3} with it" -f $paper, $bare, $covered)
            if ([Math]::Abs($covered - $bare) -lt 0.005) { throw "The $paper overlay did not change the screen" }
        } finally {
            Stop-Deckle $deckle
        }
    }

    # Open the tray menu the way the shell does: NOTIFYICON_VERSION_4 sends
    # WM_CONTEXTMENU in lParam and the anchor point in wParam.
    $deckle = Start-Deckle 'classic-matte' 0.22
    try {
        $x = $screen.Right - 140
        $y = $screen.Bottom - 60
        $anchor = [IntPtr](($y -shl 16) -bor $x)
        [Native]::PostMessageW($deckle.Tray, 0x8001, $anchor, [IntPtr]0x007B) | Out-Null
        Start-Sleep -Seconds 1
        Save-Screen 'tray-menu' | Out-Null
        # Best effort: open the Paper submenu from the keyboard.
        try {
            [System.Windows.Forms.SendKeys]::SendWait('p')
            Start-Sleep -Milliseconds 300
            [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}')
            Start-Sleep -Seconds 1
            Save-Screen 'paper-menu' | Out-Null
            [System.Windows.Forms.SendKeys]::SendWait('{ESC}{ESC}')
        } catch {
            Write-Host "Could not open the Paper submenu: $_"
        }
    } finally {
        Stop-Deckle $deckle
    }
} finally {
    if ($notepad) { Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
