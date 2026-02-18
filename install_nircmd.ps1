# NirCmd Auto-Installer for Windows
# NirCmd is a command-line utility for controlling Windows audio devices
# Encoding: UTF-8 without BOM

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "$env:USERPROFILE\nircmd",
    
    [Parameter()]
    [switch]$SystemWide,
    
    [Parameter()]
    [switch]$Force
)

# Set error handling
$ErrorActionPreference = "Stop"

# Color output functions
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
Write-Info "   NirCmd Auto-Installer for Windows"
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
    $InstallPath = "C:\nircmd"
}

# Check if already installed
Write-Info "[1/5] Checking if NirCmd is already installed..."
$existingNirCmd = Get-Command nircmd -ErrorAction SilentlyContinue

if ($existingNirCmd) {
    Write-Success "[OK] NirCmd found: $($existingNirCmd.Source)"
    
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
Write-Info "`n[2/5] Creating installation directory: $InstallPath"
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Success "[OK] Directory created"
} else {
    Write-Success "[OK] Directory exists"
}

# Download NirCmd
Write-Info "`n[3/5] Downloading NirCmd..."

# Detect system architecture
if ([Environment]::Is64BitOperatingSystem) {
    $downloadUrl = "https://www.nirsoft.net/utils/nircmd-x64.zip"
    $arch = "x64"
} else {
    $downloadUrl = "https://www.nirsoft.net/utils/nircmd.zip"
    $arch = "x86"
}

$zipFile = "$env:TEMP\nircmd_download.zip"

Write-Host "Architecture: $arch" -ForegroundColor Gray
Write-Host "Source: $downloadUrl" -ForegroundColor Gray

try {
    # Set TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Download
    $progressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
    
    $fileSize = [math]::Round((Get-Item $zipFile).Length / 1KB, 2)
    Write-Success "[OK] Downloaded: $fileSize KB"
} catch {
    Write-Error "[FAIL] Download failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Warning "Please download manually:"
    Write-Warning "  1. Visit: https://www.nirsoft.net/utils/nircmd.html"
    Write-Warning "  2. Download: nircmd-x64.zip (or nircmd.zip for 32-bit)"
    Write-Warning "  3. Extract nircmd.exe to: $InstallPath"
    exit 1
}

# Extract files
Write-Info "`n[4/5] Extracting NirCmd..."

try {
    # Extract directly to install path
    Expand-Archive -Path $zipFile -DestinationPath $InstallPath -Force
    
    # Verify extraction
    $nircmdExe = Join-Path $InstallPath "nircmd.exe"
    if (Test-Path $nircmdExe) {
        Write-Success "[OK] Extraction complete"
    } else {
        throw "nircmd.exe not found after extraction"
    }
} catch {
    Write-Error "[FAIL] Extraction failed: $($_.Exception.Message)"
    exit 1
} finally {
    # Clean up zip file
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    }
}

# Configure environment variable
Write-Info "`n[5/5] Configuring environment variable..."

if ($SystemWide) {
    $scope = "Machine"
} else {
    $scope = "User"
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", $scope)

if ($currentPath -notlike "*$InstallPath*") {
    $newPath = $currentPath.TrimEnd(';') + ";" + $InstallPath
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
Write-Info "`n[Verification] Testing NirCmd..."
$nircmdExe = Join-Path $InstallPath "nircmd.exe"

if (Test-Path $nircmdExe) {
    Write-Success "[OK] nircmd.exe found"
    
    # Try to run nircmd
    try {
        $result = & $nircmdExe cmdwait 1000 echo "NirCmd is working!"
        Write-Success "[OK] NirCmd executable verified"
    } catch {
        Write-Warning "[WARN] Cannot run nircmd (may need restart)"
    }
} else {
    Write-Error "[FAIL] nircmd.exe not found"
    exit 1
}

# Summary
Write-Host ""
Write-Info "========================================"
Write-Success "   Installation Complete!"
Write-Info "========================================"
Write-Host ""
Write-Host "[Install Location] $InstallPath" -ForegroundColor White
Write-Host "[Executable Path]  $InstallPath\nircmd.exe" -ForegroundColor White
Write-Host "[Environment Var]  $scope PATH" -ForegroundColor White
Write-Host ""
Write-Warning "[IMPORTANT] Please restart PowerShell/Terminal for PATH to take effect"
Write-Host ""
Write-Info "[Quick Test] Run in a new terminal:"
Write-Host "  nircmd speak text `"Hello from NirCmd`"" -ForegroundColor Gray
Write-Host ""

# Ask to test now
$testNow = Read-Host "Test in new window now? (y/n)"
if ($testNow -eq 'y') {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host 'Testing NirCmd...' -ForegroundColor Cyan; nircmd speak text 'NirCmd is working'; Write-Host ''; Write-Host 'Common NirCmd commands:' -ForegroundColor Cyan; Write-Host '  nircmd.exe setsysvolume 65535  (set volume to 100%)' -ForegroundColor Gray; Write-Host '  nircmd.exe mutesysvolume 1     (mute)' -ForegroundColor Gray; Write-Host '  nircmd.exe mutesysvolume 0     (unmute)' -ForegroundColor Gray; Write-Host ''; Write-Host 'Press any key to close...' -ForegroundColor Yellow; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')"
}

Write-Success "`nInstallation script completed!"
Write-Host ""
Write-Host "Common NirCmd commands:" -ForegroundColor Cyan
Write-Host "  nircmd.exe setsysvolume 65535     # Set volume to 100%" -ForegroundColor Gray
Write-Host "  nircmd.exe mutesysvolume 1        # Mute system" -ForegroundColor Gray
Write-Host "  nircmd.exe mutesysvolume 0        # Unmute system" -ForegroundColor Gray
Write-Host "  nircmd.exe changeappvolume firefox.exe 0.5  # Set app volume" -ForegroundColor Gray
Write-Host "  nircmd.exe setdefaultsounddevice `"Speakers`"  # Change audio device" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation: https://www.nirsoft.net/utils/nircmd.html" -ForegroundColor Cyan
Write-Host ""
