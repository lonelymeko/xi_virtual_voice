# FFmpeg Auto-Installer for Windows
# Supports Windows 10/11
# Encoding: UTF-8 without BOM

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "$env:USERPROFILE\ffmpeg",
    
    [Parameter()]
    [switch]$SystemWide,
    
    [Parameter()]
    [switch]$Force
)

# Set error handling
$ErrorActionPreference = "Stop"

# Color output function
function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

# Title
Write-Host ""
Write-Info "========================================"
Write-Info "   FFmpeg Auto-Installer for Windows"
Write-Info "========================================"
Write-Host ""

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($SystemWide -and -not $isAdmin) {
    Write-Error "[ERROR] System-wide installation requires administrator rights"
    Write-Warning "[HINT] Run PowerShell as Administrator"
    exit 1
}

if ($SystemWide) {
    $InstallPath = "C:\ffmpeg"
}

# Check if already installed
Write-Info "[1/6] Checking if FFmpeg is already installed..."
$existingFFmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue

if ($existingFFmpeg) {
    Write-Success "[OK] FFmpeg found: $($existingFFmpeg.Source)"
    & ffmpeg -version 2>&1 | Select-Object -First 1
    
    if (-not $Force) {
        Write-Host ""
        $response = Read-Host "Reinstall? (y/n)"
        if ($response -ne 'y') {
            Write-Warning "`nInstallation cancelled"
            exit 0
        }
    }
}

# Create installation directory
Write-Info "`n[2/6] Creating installation directory: $InstallPath"
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Success "[OK] Directory created"
} else {
    Write-Success "[OK] Directory exists"
}

# Download FFmpeg
Write-Info "`n[3/6] Downloading FFmpeg..."
$downloadUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$zipFile = "$env:TEMP\ffmpeg_download.zip"

Write-Host "Source: $downloadUrl" -ForegroundColor Gray
Write-Host "This may take a few minutes..." -ForegroundColor Gray

try {
    # Set TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Download with progress
    $progressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
    
    $fileSize = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)
    Write-Success "[OK] Downloaded: $fileSize MB"
} catch {
    Write-Error "[FAIL] Download failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Warning "Please download manually:"
    Write-Warning "  1. Visit: https://github.com/BtbN/FFmpeg-Builds/releases"
    Write-Warning "  2. Download: ffmpeg-master-latest-win64-gpl.zip"
    Write-Warning "  3. Extract to: $InstallPath"
    exit 1
}

# Extract files
Write-Info "`n[4/6] Extracting FFmpeg..."
$tempExtractPath = "$InstallPath\temp_extract"

try {
    # Clean old temp directory
    if (Test-Path $tempExtractPath) {
        Remove-Item $tempExtractPath -Recurse -Force
    }
    
    # Extract
    Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
    
    # Find and move files
    $ffmpegFolder = Get-ChildItem -Path $tempExtractPath -Directory | Where-Object { $_.Name -like "ffmpeg-*" } | Select-Object -First 1
    
    if ($ffmpegFolder) {
        # Copy bin directory
        $binSource = Join-Path $ffmpegFolder.FullName "bin"
        $binDest = Join-Path $InstallPath "bin"
        
        if (Test-Path $binDest) {
            Remove-Item $binDest -Recurse -Force
        }
        Copy-Item $binSource -Destination $binDest -Recurse -Force
        
        # Copy doc directory (optional)
        $docSource = Join-Path $ffmpegFolder.FullName "doc"
        $docDest = Join-Path $InstallPath "doc"
        
        if (Test-Path $docSource) {
            if (Test-Path $docDest) {
                Remove-Item $docDest -Recurse -Force
            }
            Copy-Item $docSource -Destination $docDest -Recurse -Force
        }
        
        Write-Success "[OK] Extraction complete"
    } else {
        throw "FFmpeg directory not found"
    }
} catch {
    Write-Error "[FAIL] Extraction failed: $($_.Exception.Message)"
    exit 1
} finally {
    # Clean up temp files
    if (Test-Path $tempExtractPath) {
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    }
}

# Configure environment variable
Write-Info "`n[5/6] Configuring environment variable..."
$binPath = Join-Path $InstallPath "bin"

if ($SystemWide) {
    $scope = "Machine"
} else {
    $scope = "User"
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", $scope)

if ($currentPath -notlike "*$binPath*") {
    $newPath = $currentPath.TrimEnd(';') + ";" + $binPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
    
    # Update current session PATH
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machinePath -and $userPath) {
        $env:Path = $machinePath + ";" + $userPath
    } elseif ($machinePath) {
        $env:Path = $machinePath
    } else {
        $env:Path = $userPath
    }
    
    Write-Success "[OK] Added to $scope PATH"
} else {
    Write-Success "[OK] Already in PATH"
}

# Verify installation
Write-Info "`n[6/6] Verifying installation..."
$ffmpegExe = Join-Path $binPath "ffmpeg.exe"
$ffprobeExe = Join-Path $binPath "ffprobe.exe"
$ffplayExe = Join-Path $binPath "ffplay.exe"

$allGood = $true

if (Test-Path $ffmpegExe) {
    Write-Success "[OK] ffmpeg.exe found"
    
    # Try to run ffmpeg
    try {
        $version = & $ffmpegExe -version 2>&1 | Select-Object -First 1
        Write-Host "    $version" -ForegroundColor Gray
    } catch {
        Write-Warning "[WARN] Cannot run ffmpeg"
        $allGood = $false
    }
} else {
    Write-Error "[FAIL] ffmpeg.exe not found"
    $allGood = $false
}

if (Test-Path $ffprobeExe) {
    Write-Success "[OK] ffprobe.exe found"
} else {
    Write-Warning "[WARN] ffprobe.exe not found"
}

if (Test-Path $ffplayExe) {
    Write-Success "[OK] ffplay.exe found"
} else {
    Write-Warning "[WARN] ffplay.exe not found"
}

# Summary
Write-Host ""
Write-Info "========================================"
if ($allGood) {
    Write-Success "   Installation Complete!"
} else {
    Write-Warning "   Installation Complete with Warnings"
}
Write-Info "========================================"
Write-Host ""
Write-Host "[Install Location] $InstallPath" -ForegroundColor White
Write-Host "[Executable Path]  $binPath\ffmpeg.exe" -ForegroundColor White
Write-Host "[Environment Var]  $scope PATH" -ForegroundColor White
Write-Host ""
Write-Warning "[IMPORTANT] Please restart PowerShell/Terminal for PATH to take effect"
Write-Host ""
Write-Info "[Quick Test] Run in a new terminal:"
Write-Host "  ffmpeg -version" -ForegroundColor Gray
Write-Host ""

# Ask to test now
$testNow = Read-Host "Test in new window now? (y/n)"
if ($testNow -eq 'y') {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host 'Testing FFmpeg...' -ForegroundColor Cyan; ffmpeg -version; Write-Host ''; Write-Host 'Press any key to close...' -ForegroundColor Yellow; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')"
}

Write-Success "`nInstallation script completed!"
Write-Host ""
Write-Host "Usage examples:" -ForegroundColor Cyan
Write-Host "  ffmpeg -i input.mp3 output.wav" -ForegroundColor Gray
Write-Host "  ffmpeg -i input.mp4 -vn output.mp3" -ForegroundColor Gray
Write-Host "  ffprobe input.mp4" -ForegroundColor Gray
Write-Host ""
