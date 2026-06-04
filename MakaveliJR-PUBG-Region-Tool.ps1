# ================= AUTO ELEVATE (RUN AS ADMIN) =================
# BUG FIX #1: Removed duplicate admin check — only one block needed.
# The first block re-launches as admin then exits, so the second
# block (Write-Host "Please run as admin") was dead code and caused
# double-elevation attempts on some systems.
If (-NOT ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
# ==============================================================
<#
    MakaveliJR PUBG Region Tool
    Compatible: Windows 10 / Windows 11 (PowerShell 5.1)
#>

#region ===================== CONFIG =====================
$BackupFile = "$env:USERPROFILE\MakaveliJR_backup.json"
#endregion

#region ===================== FUNCTIONS =====================

# ----------------------------------------------------------------
#  SAVE
# ----------------------------------------------------------------
function Save-Settings {
    try {
        Write-Host ""
        Write-Host "  Reading current settings..." -ForegroundColor Yellow

        # --- TimeZone ---
        $currentTZ = Get-TimeZone

        # --- BUG FIX #2: Get-WinUILanguageOverride returns a CultureInfo object,
        #     not a string. Calling .Name extracts the actual tag (e.g. "ar-EG").
        #     Without .Name it serialises as a full object and fails on restore. ---
        $uiLang = $null
        try {
            $uiLangObj = Get-WinUILanguageOverride
            if ($uiLangObj) { $uiLang = $uiLangObj.Name }
        } catch {}
        # If no override is set, fall back to the current UI culture
        if (-not $uiLang) { $uiLang = (Get-UICulture).Name }

        # --- Language list with full keyboard/input details ---
        $langList = Get-WinUserLanguageList
        $langData = @()
        foreach ($lang in $langList) {
            $inputMethods = @()
            foreach ($im in $lang.InputMethodTips) { $inputMethods += $im }
            $langData += @{
                LanguageTag  = $lang.LanguageTag
                InputMethods = $inputMethods
            }
        }

        # --- Keyboard layouts from registry ---
        # BUG FIX #7: Sort by numeric value (1,2,3…) not string (1,10,2…)
        $regLayouts = @()
        $regPath = "HKCU:\Keyboard Layout\Preload"
        if (Test-Path $regPath) {
            $keys = Get-ItemProperty -Path $regPath
            $keys.PSObject.Properties |
                Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name } |          # <-- numeric sort fix
                ForEach-Object { $regLayouts += $_.Value }
        }

        # --- Keyboard substitutes (e.g. Arabic 101 mapped layout) ---
        $regSubstitutes = @{}
        $subPath = "HKCU:\Keyboard Layout\Substitutes"
        if (Test-Path $subPath) {
            $subs = Get-ItemProperty -Path $subPath
            $subs.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object { $regSubstitutes[$_.Name] = $_.Value }
        }

        $data = @{
            UILanguageOverride   = $uiLang                          # string now (fix #2)
            SystemLocale         = (Get-WinSystemLocale).Name
            Culture              = (Get-Culture).Name
            HomeLocation         = (Get-WinHomeLocation).GeoId
            UserLanguageList     = $langData
            KeyboardPreload      = $regLayouts
            KeyboardSubstitutes  = $regSubstitutes
            TimeZoneId           = $currentTZ.Id
            TimeZoneStdName      = $currentTZ.StandardName
            TimeZoneOffsetHours  = $currentTZ.BaseUtcOffset.TotalHours
        }

        $data | ConvertTo-Json -Depth 5 | Set-Content $BackupFile -Encoding UTF8

        Write-Host ""
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  |        Settings Saved Successfully      |" -ForegroundColor Green
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  UI Language  : $uiLang"                         -ForegroundColor Cyan
        Write-Host "  System Locale: $($data.SystemLocale)"           -ForegroundColor Cyan
        Write-Host "  Culture      : $($data.Culture)"                -ForegroundColor Cyan
        Write-Host "  Home/Country : $($data.HomeLocation)"           -ForegroundColor Cyan
        Write-Host "  TimeZone     : $($currentTZ.Id)"                -ForegroundColor Cyan
        $langTags = ($langData | ForEach-Object { $_.LanguageTag }) -join ', '
        Write-Host "  Languages    : $langTags"                        -ForegroundColor Cyan
        Write-Host "  Keyboards    : $($regLayouts -join ', ')"        -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Host "  Failed to save settings: $_" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------
#  INSTALL CHINESE LANGUAGE
# ----------------------------------------------------------------
function Install-ChineseLanguage {
    try {
        Write-Host ""
        Write-Host "  Installing Chinese (zh-CN) language pack..." -ForegroundColor Yellow

        Install-Language zh-CN -ErrorAction SilentlyContinue

        $caps = @(
            "Language.Basic~~~zh-CN~0.0.1.0",
            "Language.Handwriting~~~zh-CN~0.0.1.0",
            "Language.TextToSpeech~~~zh-CN~0.0.1.0"
        )
        foreach ($cap in $caps) {
            try { Add-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue | Out-Null } catch {}
        }

        Write-Host "  Chinese language installation completed." -ForegroundColor Green
    }
    catch {
        Write-Host "  Language installation failed: $_" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------
#  SWITCH TO CHINESE
# ----------------------------------------------------------------
function Switch-ToChinese {
    try {
        Write-Host ""
        Write-Host "  Switching system to Chinese (China)..." -ForegroundColor Yellow

        Set-WinUILanguageOverride "zh-CN"
        Set-WinSystemLocale       "zh-CN"
        Set-Culture               "zh-CN"
        Set-WinHomeLocation       45
        Set-TimeZone              "China Standard Time"

        # Build language list: zh-CN + Microsoft Pinyin keyboard
        $newList = New-WinUserLanguageList "zh-CN"
        $newList[0].InputMethodTips.Clear()
        $newList[0].InputMethodTips.Add(
            "0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA038EC515D7}"
        ) | Out-Null
        Set-WinUserLanguageList $newList -Force

        Write-Host "  System switched to Chinese successfully." -ForegroundColor Green
        Write-Host "  Please Sign Out or Restart to apply changes." -ForegroundColor Cyan
    }
    catch {
        Write-Host "  Failed to switch system: $_" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------
#  TIMEZONE SAFE RESTORE  (4 fallback steps)
# ----------------------------------------------------------------
function Set-TimeZoneSafe {
    param(
        [string]$TzId,
        [string]$TzStdName,
        [double]$TzOffsetHours
    )

    # Step 1: Try saved ID directly
    try {
        Set-TimeZone -Id $TzId -ErrorAction Stop
        Write-Host "  [OK] TimeZone: $TzId" -ForegroundColor Green
        return
    } catch {}

    # Step 2: Match by StandardName
    if ($TzStdName) {
        $match = Get-TimeZone -ListAvailable |
                 Where-Object { $_.StandardName -eq $TzStdName } |
                 Select-Object -First 1
        if ($match) {
            try {
                Set-TimeZone -Id $match.Id -ErrorAction Stop
                Write-Host "  [OK] TimeZone by StandardName: $($match.Id)" -ForegroundColor Green
                return
            } catch {}
        }
    }

    # Step 3: Match by UTC offset
    try {
        $span  = [TimeSpan]::FromHours($TzOffsetHours)
        $match = Get-TimeZone -ListAvailable |
                 Where-Object { $_.BaseUtcOffset -eq $span } |
                 Select-Object -First 1
        if ($match) {
            Set-TimeZone -Id $match.Id -ErrorAction Stop
            Write-Host "  [~] TimeZone by UTC offset (UTC+$($TzOffsetHours)h): $($match.Id)" -ForegroundColor Yellow
            return
        }
    } catch {}

    # Step 4: Partial ID keyword match
    try {
        $keyword = $TzId.Split(' ')[0]
        $match   = Get-TimeZone -ListAvailable |
                   Where-Object { $_.Id -like "*$keyword*" } |
                   Select-Object -First 1
        if ($match) {
            Set-TimeZone -Id $match.Id -ErrorAction Stop
            Write-Host "  [~] TimeZone partial match: $($match.Id)" -ForegroundColor Yellow
            return
        }
    } catch {}

    Write-Host "  [!] Could not restore timezone '$TzId'" -ForegroundColor Red
    Write-Host "      Fix manually: Settings > Time & Language > Date & Time" -ForegroundColor DarkYellow
}

# ----------------------------------------------------------------
#  RESTORE
# ----------------------------------------------------------------
function Restore-Settings {
    try {
        if (!(Test-Path $BackupFile)) {
            Write-Host ""
            Write-Host "  [!] Backup file not found!" -ForegroundColor Red
            Write-Host "      Run option 1 first to save your settings." -ForegroundColor Yellow
            return
        }

        $data = Get-Content $BackupFile -Raw | ConvertFrom-Json

        Write-Host ""
        Write-Host "  Restoring settings..." -ForegroundColor Yellow
        Write-Host ""

        # --- 1. TimeZone ---
        if ($data.TimeZoneId) {
            Set-TimeZoneSafe `
                -TzId          $data.TimeZoneId `
                -TzStdName     $data.TimeZoneStdName `
                -TzOffsetHours $data.TimeZoneOffsetHours
        }

        # --- 2. System Locale ---
        if ($data.SystemLocale) {
            Set-WinSystemLocale $data.SystemLocale
            Write-Host "  [OK] System Locale: $($data.SystemLocale)" -ForegroundColor Green
        }

        # --- 3. Culture ---
        if ($data.Culture) {
            Set-Culture $data.Culture
            Write-Host "  [OK] Culture: $($data.Culture)" -ForegroundColor Green
        }

        # --- 4. Home Location ---
        if ($data.HomeLocation) {
            Set-WinHomeLocation $data.HomeLocation
            Write-Host "  [OK] Home Location: $($data.HomeLocation)" -ForegroundColor Green
        }

        # --- 5. Language List + Keyboard Input Methods ---
        if ($data.UserLanguageList -and $data.UserLanguageList.Count -gt 0) {

            # BUG FIX #3: New-WinUserLanguageList "" crashes — use the first real
            # language tag to initialise the list, then clear & rebuild properly.
            $firstTag = $data.UserLanguageList[0].LanguageTag
            $newList  = New-WinUserLanguageList $firstTag
            $newList.Clear()

            foreach ($savedLang in $data.UserLanguageList) {
                try {
                    $langTag  = $savedLang.LanguageTag
                    $tempList = New-WinUserLanguageList $langTag
                    $langObj  = $tempList[0]

                    if ($savedLang.InputMethods -and $savedLang.InputMethods.Count -gt 0) {
                        $langObj.InputMethodTips.Clear()
                        foreach ($im in $savedLang.InputMethods) {
                            $langObj.InputMethodTips.Add($im) | Out-Null
                        }
                        Write-Host "  [OK] Language: $langTag  |  Keyboards: $($savedLang.InputMethods -join ', ')" -ForegroundColor Green
                    } else {
                        Write-Host "  [OK] Language: $langTag  |  (default keyboard)" -ForegroundColor Green
                    }

                    $newList.Add($langObj)
                }
                catch {
                    Write-Host "  [!] Could not restore language '$($savedLang.LanguageTag)': $_" -ForegroundColor Red
                }
            }

            Set-WinUserLanguageList $newList -Force
        }

        # --- 6. UI Language ---
        # BUG FIX #6: Only call Set-WinUILanguageOverride when the value is a
        # non-empty string. An empty/null value throws a terminating error.
        if ($data.UILanguageOverride -and $data.UILanguageOverride.Trim() -ne "") {
            try {
                Set-WinUILanguageOverride $data.UILanguageOverride
                Write-Host "  [OK] UI Language: $($data.UILanguageOverride)" -ForegroundColor Green
            } catch {
                Write-Host "  [!] Could not set UI language '$($data.UILanguageOverride)': $_" -ForegroundColor Red
            }
        }

        # --- 7. Keyboard Registry Preload ---
        # BUG FIX #4: ConvertFrom-Json returns PSCustomObject for arrays with one
        # element and a plain array otherwise. @() cast normalises both cases.
        $preload = @($data.KeyboardPreload)
        if ($preload.Count -gt 0) {
            try {
                $regPath = "HKCU:\Keyboard Layout\Preload"
                if (Test-Path $regPath) { Remove-Item -Path $regPath -Recurse -Force }
                New-Item -Path $regPath -Force | Out-Null

                $i = 1
                foreach ($layout in $preload) {
                    Set-ItemProperty -Path $regPath -Name "$i" -Value $layout -Type String
                    $i++
                }
                Write-Host "  [OK] Keyboard Preload registry: $($preload -join ', ')" -ForegroundColor Green
            }
            catch {
                Write-Host "  [!] Could not restore Keyboard Preload: $_" -ForegroundColor Red
            }
        }

        # --- 8. Keyboard Substitutes ---
        # BUG FIX #5: PSObject from JSON may be empty — check property count first.
        if ($data.KeyboardSubstitutes) {
            $subProps = @($data.KeyboardSubstitutes.PSObject.Properties |
                          Where-Object { $_.Name -notmatch '^PS' })
            if ($subProps.Count -gt 0) {
                try {
                    $subPath = "HKCU:\Keyboard Layout\Substitutes"
                    if (-not (Test-Path $subPath)) { New-Item -Path $subPath -Force | Out-Null }
                    foreach ($prop in $subProps) {
                        Set-ItemProperty -Path $subPath -Name $prop.Name -Value $prop.Value -Type String
                    }
                    Write-Host "  [OK] Keyboard Substitutes restored." -ForegroundColor Green
                }
                catch {
                    Write-Host "  [!] Could not restore Keyboard Substitutes: $_" -ForegroundColor Red
                }
            }
        }

        Write-Host ""
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  |      Restore Completed Successfully     |" -ForegroundColor Green
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  Sign Out or Restart to apply all changes."    -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Host "  Restore failed: $_" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------
#  MENU
# ----------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "      MakaveliJR PUBG Region Tool       " -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  YouTube: https://www.youtube.com/@KINGMAKAVELI"
    Write-Host ""
    Write-Host "  1 - Save Current Settings"
    Write-Host "  2 - Install Chinese Language"
    Write-Host "  3 - Switch To Chinese (China Region + UTC+8)"
    Write-Host "  4 - Restore Original Settings"
    Write-Host "  5 - Exit"
    Write-Host ""
}

#endregion

#region ===================== MAIN LOOP =====================
do {
    Show-Menu
    $choice = Read-Host "  Select an option"

    switch ($choice) {
        "1" { Save-Settings;           Pause }
        "2" { Install-ChineseLanguage; Pause }
        "3" { Switch-ToChinese;        Pause }
        "4" { Restore-Settings;        Pause }
        "5" { exit }
        default {
            Write-Host "  Invalid option. Try again." -ForegroundColor Red
            Start-Sleep 2
        }
    }

} while ($true)
#endregion
