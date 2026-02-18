# Install AudioDeviceCmdlets Module for Windows
# This module is required for audio device switching
# Run this script as Administrator

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",
    
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
Clear-Host
Write-Host ""
Write-Info "=============================================="
Write-Info "   AudioDeviceCmdlets Module Installer"
Write-Info "=============================================="
Write-Host ""

# Check if already installed
Write-Info "[1/4] Checking if AudioDeviceCmdlets is already installed..."
$existingModule = Get-Module -ListAvailable -Name AudioDeviceCmdlets

if ($existingModule -and -not $Force) {
    Write-Success "[OK] AudioDeviceCmdlets is already installed"
    Write-Host "    Version: $($existingModule.Version)" -ForegroundColor Gray
    Write-Host "    Location: $($existingModule.ModuleBase)" -ForegroundColor Gray
    Write-Host ""
    
    $reinstall = Read-Host "Do you want to reinstall? (y/n)"
    if ($reinstall -ne 'y') {
        Write-Info "Installation cancelled"
        exit 0
    }
}

# Set PSGallery as trusted
Write-Info "`n[2/4] Configuring PowerShell Gallery..."
try {
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($gallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-Success "[OK] PSGallery set as trusted"
    } else {
        Write-Success "[OK] PSGallery already trusted"
    }
} catch {
    Write-Warning "[WARN] Could not configure PSGallery: $($_.Exception.Message)"
}

# Install NuGet provider if needed
Write-Info "`n[3/4] Checking NuGet provider..."
try {
    $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
    if (-not $nuget) {
        Write-Info "Installing NuGet provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $Scope
        Write-Success "[OK] NuGet provider installed"
    } else {
        Write-Success "[OK] NuGet provider already installed"
    }
} catch {
    Write-Warning "[WARN] Could not install NuGet: $($_.Exception.Message)"
}

# Install AudioDeviceCmdlets
Write-Info "`n[4/4] Installing AudioDeviceCmdlets module..."
try {
    if ($Scope -eq "AllUsers") {
        Install-Module -Name AudioDeviceCmdlets -Scope AllUsers -Force -AllowClobber
    } else {
        Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force -AllowClobber
    }
    Write-Success "[OK] AudioDeviceCmdlets installed successfully"
} catch {
    Write-Error "[FAIL] Installation failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Warning "If you see 'Access denied' error, try:"
    Write-Host "  1. Run PowerShell as Administrator" -ForegroundColor Yellow
    Write-Host "  2. Use -Scope CurrentUser parameter" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Verify installation
Write-Host ""
Write-Info "=============================================="
Write-Info "   Verifying Installation"
Write-Info "=============================================="

try {
    Import-Module AudioDeviceCmdlets -ErrorAction Stop
    $module = Get-Module AudioDeviceCmdlets
    
    Write-Success "`n[OK] Module loaded successfully"
    Write-Host "    Name: $($module.Name)" -ForegroundColor Gray
    Write-Host "    Version: $($module.Version)" -ForegroundColor Gray
    Write-Host "    Author: $($module.Author)" -ForegroundColor Gray
    Write-Host ""
    
    # Test commands
    Write-Info "Available Commands:"
    $commands = Get-Command -Module AudioDeviceCmdlets | Select-Object -ExpandProperty Name
    foreach ($cmd in $commands) {
        Write-Host "  - $cmd" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Test getting devices
    Write-Info "Testing: Get-AudioDevice -List"
    $devices = Get-AudioDevice -List
    Write-Success "[OK] Found $($devices.Count) audio devices"
    
    Write-Host ""
    Write-Info "Playback Devices:"
    $devices | Where-Object {$_.Type -eq "Playback"} | ForEach-Object {
        $marker = if ($_.Default) {"[Default]"} else {"         "}
        Write-Host "  $marker $($_.Name)" -ForegroundColor $(if ($_.Default) {"Green"} else {"Gray"})
    }
    
    Write-Host ""
    Write-Info "Recording Devices:"
    $devices | Where-Object {$_.Type -eq "Recording"} | ForEach-Object {
        $marker = if ($_.Default) {"[Default]"} else {"         "}
        Write-Host "  $marker $($_.Name)" -ForegroundColor $(if ($_.Default) {"Green"} else {"Gray"})
    }
    
} catch {
    Write-Error "[FAIL] Verification failed: $($_.Exception.Message)"
    exit 1
}

# Summary
Write-Host ""
Write-Info "=============================================="
Write-Success "   Installation Complete!"
Write-Info "=============================================="
Write-Host ""
Write-Host "[Module Information]" -ForegroundColor White
Write-Host "  Name: AudioDeviceCmdlets" -ForegroundColor Gray
Write-Host "  Version: $($module.Version)" -ForegroundColor Gray
Write-Host "  Scope: $Scope" -ForegroundColor Gray
Write-Host ""
Write-Host "[Usage Examples]" -ForegroundColor White
Write-Host "  Get-AudioDevice -List              # List all devices" -ForegroundColor Gray
Write-Host "  Get-AudioDevice -Playback          # Get default playback" -ForegroundColor Gray
Write-Host "  Set-AudioDevice -Name 'DeviceName' # Switch device" -ForegroundColor Gray
Write-Host ""
Write-Success "You can now use xi_virtual_voice with audio device switching!"
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Gray
Read-Host
