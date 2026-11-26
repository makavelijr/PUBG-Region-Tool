#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===================== AUTO ELEVATE =====================
# ASCII-only file. PS 5.1 reads BOM-less UTF-8 as ANSI.
$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $psExe)) { $psExe = 'powershell.exe' }

if (-not ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
          [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    try {
        Start-Process -FilePath $psExe -ArgumentList $argLine -Verb RunAs -ErrorAction Stop | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Elevation failed or was cancelled: $_`n`nPlease run from an elevated PowerShell window.",
            'MakaveliJR Tool', 'OK', 'Error') | Out-Null
    }
    exit
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    if (Test-Path $psExe) {
        Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) | Out-Null
    }
    exit
}
# ========================================================

[System.Windows.Forms.Application]::EnableVisualStyles()

#region ===================== CONFIG =====================
$BackupFile    = Join-Path $env:USERPROFILE 'MakaveliJR_backup.json'
$SchemaVersion = 2
$script:LogBox = $null
$script:ButtonList = @()
#endregion

#region ===================== GUI LOG (Write-Host override) =====================
function Convert-ConsoleColor {
    param([ConsoleColor]$Color)
    switch ($Color.ToString()) {
        'Green'      { return [System.Drawing.Color]::DarkGreen }
        'Red'        { return [System.Drawing.Color]::Firebrick }
        'Yellow'     { return [System.Drawing.Color]::DarkGoldenrod }
        'Cyan'       { return [System.Drawing.Color]::Teal }
        'DarkYellow' { return [System.Drawing.Color]::Olive }
        'DarkGray'   { return [System.Drawing.Color]::Gray }
        'DarkCyan'   { return [System.Drawing.Color]::DarkCyan }
        default      { return [System.Drawing.Color]::Black }
    }
}

function Append-Log {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Black, [switch]$NoNewline)
    if ($null -eq $script:LogBox) { return }
    $script:LogBox.SelectionColor = Convert-ConsoleColor $Color
    $script:LogBox.AppendText($Text)
    if (-not $NoNewline) { $script:LogBox.AppendText("`r`n") }
    $script:LogBox.SelectionColor = $script:LogBox.ForeColor
    $script:LogBox.ScrollToCaret()
}

# All core functions below call Write-Host. Redirect them into the GUI log.
function Write-Host {
    param(
        [Parameter(Position = 0)][object]$Object,
        [string]$Separator = ' ',
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Black,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )
    if ($null -eq $script:LogBox) { return }
    Append-Log -Text ([string]$Object) -Color $ForegroundColor -NoNewline:$NoNewline
}
#endregion

#region ===================== HELPERS =====================
function Test-Cmdlet {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Host "  [OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!] $Name : $_" -ForegroundColor Red
    }
}

function Set-TimeZoneSafe {
    param([string]$TzId, [string]$TzStdName, [double]$TzOffsetHours)

    if (-not $TzId) { return }

    if (Test-Cmdlet 'Set-TimeZone') {
        try {
            Set-TimeZone -Id $TzId -ErrorAction Stop
            Write-Host "  [OK] TimeZone: $TzId" -ForegroundColor Green
            return
        } catch {}
    }
    else {
        try {
            & tzutil /s $TzId 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] TimeZone (tzutil): $TzId" -ForegroundColor Green
                return
            }
        } catch {}
    }

    if ($TzStdName -and (Test-Cmdlet 'Get-TimeZone')) {
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

    if (Test-Cmdlet 'Get-TimeZone') {
        $candidates = @()
        try {
            $span = [TimeSpan]::FromHours($TzOffsetHours)
            $candidates = @(Get-TimeZone -ListAvailable | Where-Object { $_.BaseUtcOffset -eq $span })
        } catch {}
        if ($candidates.Count -eq 1) {
            try {
                Set-TimeZone -Id $candidates[0].Id -ErrorAction Stop
                Write-Host "  [~] TimeZone by UTC offset: $($candidates[0].Id)" -ForegroundColor Yellow
                return
            } catch {}
        }
        elseif ($candidates.Count -gt 1) {
            Write-Host "  [!] UTC$TzOffsetHours matches $($candidates.Count) zones - not guessing." -ForegroundColor Yellow
        }
    }

    try {
        $keyword = ($TzId -split ' ')[0]
        $match = @(& tzutil /l | Where-Object { $_ -like "*$keyword*" } | Select-Object -First 1)[0]
        if ($match) {
            & tzutil /s $match 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [~] TimeZone keyword match: $match" -ForegroundColor Yellow
                return
            }
        }
    } catch {}

    Write-Host "  [!] Could not restore timezone '$TzId'. Set it manually." -ForegroundColor Red
}

function Show-Compatibility {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "  OS          : $($os.Caption) (build $($os.BuildNumber))" -ForegroundColor Cyan
    Write-Host "  PowerShell  : $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)" -ForegroundColor Cyan
    Write-Host "  Administrator: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" -ForegroundColor Cyan
    Write-Host "  tzutil.exe  : $(Test-Cmdlet 'tzutil')" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Cmdlet availability:" -ForegroundColor Yellow
    $checks = @(
        'Get-TimeZone', 'Set-TimeZone',
        'Get-WinUserLanguageList', 'Set-WinUserLanguageList', 'New-WinUserLanguageList',
        'Get-WinUILanguageOverride', 'Set-WinUILanguageOverride',
        'Set-WinSystemLocale', 'Set-Culture', 'Set-WinHomeLocation',
        'Install-Language', 'Add-WindowsCapability'
    )
    foreach ($c in $checks) {
        $ok = Test-Cmdlet $c
        Write-Host ("    [{0}] {1}" -f $(if ($ok) { 'OK' } else { '--' }), $c) -ForegroundColor $(if ($ok) { 'Green' } else { 'DarkYellow' })
    }
    Write-Host ""
    Write-Host "  Notes:" -ForegroundColor Yellow
    Write-Host "    - Install-Language      : Windows 10 1809+ / Server 2019+"
    Write-Host "    - Add-WindowsCapability : Windows 10 1607+ / Server 2016+"
    Write-Host "    - International cmdlets : Windows 8+ / Server 2012+"
    Write-Host "    - Missing cmdlets are skipped with a warning, never crash the tool."
    Write-Host ""
}
#endregion

#region ===================== SAVE =====================
function Save-Settings {
    try {
        Write-Host ""
        Write-Host "  Reading current settings..." -ForegroundColor Yellow

        $tzId = $null; $tzStd = $null; $tzOff = 0
        if (Test-Cmdlet 'Get-TimeZone') {
            $tz = Get-TimeZone
            $tzId = $tz.Id; $tzStd = $tz.StandardName; $tzOff = $tz.BaseUtcOffset.TotalHours
        }
        else {
            try { $tzId = (& tzutil /g).Trim() } catch {}
            $wmi = Get-CimInstance Win32_TimeZone -ErrorAction SilentlyContinue
            if ($wmi) { $tzStd = $wmi.StandardName; $tzOff = -[double]$wmi.Bias / 60 }
        }

        $overrideObj = $null
        if (Test-Cmdlet 'Get-WinUILanguageOverride') {
            $overrideObj = Get-WinUILanguageOverride -ErrorAction SilentlyContinue
        }
        $hasOverride = [bool]$overrideObj
        $uiLang = if ($hasOverride) { $overrideObj.Name } else { $null }

        $langData = @()
        if (Test-Cmdlet 'Get-WinUserLanguageList') {
            foreach ($lang in (Get-WinUserLanguageList)) {
                $langData += @{
                    LanguageTag  = $lang.LanguageTag
                    InputMethods = @($lang.InputMethodTips)
                }
            }
        }
        else {
            Write-Host "  [!] Get-WinUserLanguageList unavailable - language list not saved." -ForegroundColor Yellow
        }

        $regLayouts = @()
        $regPath = 'HKCU:\Keyboard Layout\Preload'
        if (Test-Path $regPath) {
            (Get-ItemProperty -Path $regPath).PSObject.Properties |
                Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name } |
                ForEach-Object { $regLayouts += [string]$_.Value }
        }

        $regSubstitutes = @{}
        $subPath = 'HKCU:\Keyboard Layout\Substitutes'
        if (Test-Path $subPath) {
            (Get-ItemProperty -Path $subPath).PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object { $regSubstitutes[$_.Name] = [string]$_.Value }
        }

        $data = [ordered]@{
            SchemaVersion         = $SchemaVersion
            HasUILanguageOverride = $hasOverride
            UILanguageOverride    = $uiLang
            SystemLocale          = if (Test-Cmdlet 'Get-WinSystemLocale') { (Get-WinSystemLocale).Name } else { $null }
            Culture               = (Get-Culture).Name
            HomeLocation          = if (Test-Cmdlet 'Get-WinHomeLocation') { (Get-WinHomeLocation).GeoId } else { $null }
            UserLanguageList      = $langData
            KeyboardPreload       = $regLayouts
            KeyboardSubstitutes   = $regSubstitutes
            TimeZoneId            = $tzId
            TimeZoneStdName       = $tzStd
            TimeZoneOffsetHours   = $tzOff
        }

        $data | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8

        Write-Host ""
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  |        Settings Saved Successfully      |" -ForegroundColor Green
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  UI Language  : $(if ($uiLang) { $uiLang } else { '(none - follows language list)' })" -ForegroundColor Cyan
        Write-Host "  System Locale: $($data.SystemLocale)"            -ForegroundColor Cyan
        Write-Host "  Culture      : $($data.Culture)"                 -ForegroundColor Cyan
        Write-Host "  Home/Country : $($data.HomeLocation)"            -ForegroundColor Cyan
        Write-Host "  TimeZone     : $tzId"                            -ForegroundColor Cyan
        Write-Host "  Languages    : $(($langData.LanguageTag) -join ', ')" -ForegroundColor Cyan
        Write-Host "  Keyboards    : $($regLayouts -join ', ')"         -ForegroundColor Cyan
        Write-Host "  Backup       : $BackupFile"                      -ForegroundColor DarkGray
        Write-Host ""
    }
    catch {
        Write-Host "  Failed to save settings: $_" -ForegroundColor Red
    }
}
#endregion

#region ===================== INSTALL CHINESE =====================
function Install-ChineseLanguage {
    Write-Host ""
    Write-Host "  Installing Chinese (zh-CN) language pack..." -ForegroundColor Yellow

    Invoke-Step 'Install-Language zh-CN' {
        Install-Language -Language zh-CN -ErrorAction Stop | Out-Null
    }

    $caps = @(
        'Language.Basic~~~zh-CN~0.0.1.0',
        'Language.Handwriting~~~zh-CN~0.0.1.0',
        'Language.TextToSpeech~~~zh-CN~0.0.1.0'
    )
    foreach ($cap in $caps) {
        Invoke-Step $cap {
            Add-WindowsCapability -Online -Name $cap -ErrorAction Stop | Out-Null
        }
    }
    Write-Host "  Sign out / restart once before using option 3." -ForegroundColor Cyan
}
#endregion

#region ===================== SWITCH TO CHINESE =====================
function Switch-ToChinese {
    Write-Host ""
    Write-Host "  Switching system to Chinese (China)..." -ForegroundColor Yellow

    if ((Test-Cmdlet 'New-WinUserLanguageList') -and (Test-Cmdlet 'Set-WinUserLanguageList')) {
        Invoke-Step 'User language list (zh-CN + Pinyin)' {
            $newList = New-WinUserLanguageList 'zh-CN'
            $newList[0].InputMethodTips.Clear()
            $newList[0].InputMethodTips.Add(
                '0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA038EC515D7}'
            ) | Out-Null
            Set-WinUserLanguageList -LanguageList $newList -Force -ErrorAction Stop
        }
    }
    else {
        Write-Host "  [!] User-language cmdlets unavailable - list unchanged." -ForegroundColor Yellow
    }

    Invoke-Step 'UI language override' { Set-WinUILanguageOverride 'zh-CN' -ErrorAction Stop }
    Invoke-Step 'System locale'        { Set-WinSystemLocale 'zh-CN' -ErrorAction Stop }
    Invoke-Step 'Culture'              { Set-Culture 'zh-CN' -ErrorAction Stop }
    Invoke-Step 'Home location (CN)'   { Set-WinHomeLocation 45 -ErrorAction Stop }
    Set-TimeZoneSafe -TzId 'China Standard Time'

    Write-Host ""
    Write-Host "  Sign Out or Restart to apply all changes." -ForegroundColor Cyan
}
#endregion

#region ===================== RESTORE =====================
function Restore-Settings {
    try {
        if (-not (Test-Path $BackupFile)) {
            Write-Host ""
            Write-Host "  [!] Backup file not found: $BackupFile" -ForegroundColor Red
            Write-Host "      Run option 1 first." -ForegroundColor Yellow
            return
        }

        $data = Get-Content $BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $names = @($data.PSObject.Properties.Name)
        $legacy = ($names -notcontains 'SchemaVersion')

        Write-Host ""
        Write-Host "  Restoring settings..." -ForegroundColor Yellow
        if ($legacy) {
            Write-Host "  [!] OLD backup format (no SchemaVersion)." -ForegroundColor Red
            Write-Host "      Timezone/language/keyboard data may be missing." -ForegroundColor Yellow
            Write-Host "      Only safe fields are restored. Run option 1 for a full backup." -ForegroundColor Yellow
        }
        Write-Host ""

        $tzId = if ($data.TimeZoneId) { $data.TimeZoneId }
                elseif ($legacy -and $data.TimeZone) { $data.TimeZone }
                else { $null }
        Set-TimeZoneSafe -TzId $tzId -TzStdName $data.TimeZoneStdName -TzOffsetHours $data.TimeZoneOffsetHours

        if (Test-Cmdlet 'Set-WinSystemLocale') {
            Invoke-Step 'System Locale' {
                if ($data.SystemLocale) { Set-WinSystemLocale $data.SystemLocale -ErrorAction Stop }
                else { throw 'missing value in backup' }
            }
        } else { Write-Host "  [--] System Locale cmdlet unavailable - skipped." -ForegroundColor DarkYellow }

        Invoke-Step 'Culture' {
            if ($data.Culture) { Set-Culture $data.Culture -ErrorAction Stop }
            else { throw 'missing value in backup' }
        }

        if (Test-Cmdlet 'Set-WinHomeLocation') {
            Invoke-Step 'Home Location' {
                if ($null -ne $data.HomeLocation) { Set-WinHomeLocation $data.HomeLocation -ErrorAction Stop }
                else { throw 'missing value in backup' }
            }
        } else { Write-Host "  [--] Home Location cmdlet unavailable - skipped." -ForegroundColor DarkYellow }

        if (-not $legacy) {
            if ((Test-Cmdlet 'New-WinUserLanguageList') -and (Test-Cmdlet 'Set-WinUserLanguageList')) {
                $savedLangs = @($data.UserLanguageList) | Where-Object { $_ -and $_.LanguageTag }
                if ($savedLangs.Count -gt 0) {
                    Invoke-Step 'User language list' {
                        $newList = New-WinUserLanguageList $savedLangs[0].LanguageTag
                        $newList.Clear()
                        foreach ($savedLang in $savedLangs) {
                            $langObj = (New-WinUserLanguageList $savedLang.LanguageTag)[0]
                            $langObj.InputMethodTips.Clear()
                            foreach ($im in @($savedLang.InputMethods)) {
                                if ($im) { $langObj.InputMethodTips.Add([string]$im) | Out-Null }
                            }
                            $newList.Add($langObj)
                        }
                        Set-WinUserLanguageList -LanguageList $newList -Force -ErrorAction Stop
                    }
                }
                else {
                    Write-Host "  [!] No usable language list in backup - skipped." -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  [--] User-language cmdlets unavailable - list unchanged." -ForegroundColor DarkYellow
            }

            if (Test-Cmdlet 'Set-WinUILanguageOverride') {
                Invoke-Step 'UI language override' {
                    if ($data.HasUILanguageOverride -and $data.UILanguageOverride) {
                        Set-WinUILanguageOverride $data.UILanguageOverride -ErrorAction Stop
                    }
                    else {
                        Set-WinUILanguageOverride -ErrorAction Stop
                    }
                }
            }
            else {
                Write-Host "  [--] UI override cmdlet unavailable - skipped." -ForegroundColor DarkYellow
            }
        }

        if (-not $legacy) {
            $preload = @($data.KeyboardPreload) | Where-Object { $_ }
            if ($preload.Count -gt 0) {
                Invoke-Step 'Keyboard Preload registry' {
                    $regPath = 'HKCU:\Keyboard Layout\Preload'
                    if (Test-Path $regPath) { Remove-Item $regPath -Recurse -Force }
                    New-Item $regPath -Force | Out-Null
                    $i = 1
                    foreach ($layout in $preload) {
                        Set-ItemProperty -Path $regPath -Name "$i" -Value ([string]$layout) -Type String
                        $i++
                    }
                }
            }
            else {
                Write-Host "  [!] No keyboard preload data in backup - registry left untouched." -ForegroundColor Yellow
            }

            $subProps = @()
            if ($data.KeyboardSubstitutes) {
                $subProps = @($data.KeyboardSubstitutes.PSObject.Properties |
                              Where-Object { $_.Name -notmatch '^PS' })
            }
            Invoke-Step 'Keyboard Substitutes registry' {
                $subPath = 'HKCU:\Keyboard Layout\Substitutes'
                if (Test-Path $subPath) { Remove-Item $subPath -Recurse -Force }
                New-Item $subPath -Force | Out-Null
                foreach ($prop in $subProps) {
                    Set-ItemProperty -Path $subPath -Name $prop.Name -Value ([string]$prop.Value) -Type String
                }
            }
        }

        Write-Host ""
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  |      Restore Finished (check warnings)  |" -ForegroundColor Green
        Write-Host "  +-----------------------------------------+" -ForegroundColor Green
        Write-Host "  Sign Out or Restart to apply all changes." -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Host "  Restore failed: $_" -ForegroundColor Red
    }
}
#endregion

#region ===================== GUI BUILD =====================
function Update-Status {
    try {
        $langs = @()
        if (Test-Cmdlet 'Get-WinUserLanguageList') {
            $langs = @(Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag })
        }
        $lblLang.Text = if ($langs.Count) { $langs -join ', ' } else { 'n/a' }

        $kb = @()
        $rp = 'HKCU:\Keyboard Layout\Preload'
        if (Test-Path $rp) {
            $kb = @((Get-ItemProperty $rp).PSObject.Properties |
                    Where-Object { $_.Name -match '^\d+$' } |
                    Sort-Object { [int]$_.Name } |
                    ForEach-Object { [string]$_.Value })
        }
        $lblKb.Text = if ($kb.Count) { $kb -join ', ' } else { 'n/a' }

        if (Test-Cmdlet 'Get-TimeZone') { $lblTz.Text = (Get-TimeZone).Id }
        else { try { $lblTz.Text = (& tzutil /g).Trim() } catch { $lblTz.Text = 'n/a' } }

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $lblAdmin.Text = if ($isAdmin) { 'Yes' } else { 'No' }
    }
    catch {
        Append-Log "Status refresh failed: $_" Red
    }
}

function New-ActionButton {
    param(
        [string]$Name,
        [string]$Description,
        [System.Drawing.Color]$Color,
        [scriptblock]$Action
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Size = New-Object System.Drawing.Size(300, 66)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $b.Text = "$Name`n$Description"
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $b.Tag = @{ Name = $Name; Action = $Action }
    $b.Add_Click({
        $t = $this.Tag
        Invoke-Action -Name $t.Name -Action $t.Action
    })
    $script:ButtonList += $b
    return $b
}

function Invoke-Action {
    param([string]$Name, [scriptblock]$Action)
    foreach ($b in $script:ButtonList) { $b.Enabled = $false }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Append-Log ""
    Append-Log "===== $Name =====" ([ConsoleColor]::Cyan)
    try {
        & $Action
    }
    catch {
        Append-Log "ERROR: $_" ([ConsoleColor]::Red)
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        foreach ($b in $script:ButtonList) { $b.Enabled = $true }
        Update-Status
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'MakaveliJR PUBG Region Tool - GUI'
$form.Size = New-Object System.Drawing.Size(960, 650)
$form.MinimumSize = New-Object System.Drawing.Size(820, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 248)

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.RowCount = 3
$root.ColumnCount = 1
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 74))) | Out-Null
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 96))) | Out-Null
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$form.Controls.Add($root)

# --- Header ---
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Fill
$header.BackColor = [System.Drawing.Color]::FromArgb(0, 96, 126)
$title = New-Object System.Windows.Forms.Label
$title.Text = '  MakaveliJR PUBG Region Tool'
$title.Dock = [System.Windows.Forms.DockStyle]::Top
$title.Height = 42
$title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '  Save, switch and restore Windows region / language settings'
$subtitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 232, 242)
$subtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$header.Controls.Add($subtitle)
$header.Controls.Add($title)
$root.Controls.Add($header, 0, 0)

# --- Status panel ---
$status = New-Object System.Windows.Forms.GroupBox
$status.Text = 'Current status'
$status.Dock = [System.Windows.Forms.DockStyle]::Fill
$status.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$status.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)
$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grid.RowCount = 2
$grid.ColumnCount = 4
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 20))) | Out-Null
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
for ($i = 0; $i -lt 4; $i++) {
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
}
$captions = @('LANGUAGES', 'KEYBOARD LAYOUTS', 'TIME ZONE', 'ADMIN RIGHTS')
foreach ($i in 0..3) {
    $cap = New-Object System.Windows.Forms.Label
    $cap.Text = $captions[$i]
    $cap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $cap.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $cap.ForeColor = [System.Drawing.Color]::FromArgb(110, 118, 128)
    $cap.TextAlign = [System.Drawing.ContentAlignment]::BottomCenter
    $grid.Controls.Add($cap, $i, 0)
}
$lblLang  = New-Object System.Windows.Forms.Label
$lblKb    = New-Object System.Windows.Forms.Label
$lblTz    = New-Object System.Windows.Forms.Label
$lblAdmin = New-Object System.Windows.Forms.Label
foreach ($pair in @(@($lblLang,0),@($lblKb,1),@($lblTz,2),@($lblAdmin,3))) {
    $l = $pair[0]
    $l.Dock = [System.Windows.Forms.DockStyle]::Fill
    $l.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = [System.Drawing.Color]::FromArgb(0, 96, 126)
    $l.TextAlign = [System.Drawing.ContentAlignment]::TopCenter
    $grid.Controls.Add($l, $pair[1], 1)
}
$status.Controls.Add($grid)
$root.Controls.Add($status, 1, 0)

# --- Buttons + log ---
$content = New-Object System.Windows.Forms.TableLayoutPanel
$content.Dock = [System.Windows.Forms.DockStyle]::Fill
$content.ColumnCount = 2
$content.RowCount = 1
$content.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 330))) | Out-Null
$content.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttons.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$buttons.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

$buttons.Controls.Add((New-ActionButton -Name '1  SAVE' -Description 'Back up language, keyboard and timezone' -Color ([System.Drawing.Color]::FromArgb(35, 130, 180)) -Action { Save-Settings }))
$buttons.Controls.Add((New-ActionButton -Name '2  INSTALL CHINESE' -Description 'Install zh-CN language pack (may take minutes)' -Color ([System.Drawing.Color]::FromArgb(45, 150, 110)) -Action { Install-ChineseLanguage }))
$buttons.Controls.Add((New-ActionButton -Name '3  SWITCH TO CHINESE' -Description 'China region + UTC+8 + Pinyin keyboard' -Color ([System.Drawing.Color]::FromArgb(200, 140, 40)) -Action {
    $r = [System.Windows.Forms.MessageBox]::Show(
        'This will replace your current language list with Chinese (zh-CN).',
        'Confirm - Switch to Chinese', 'YesNo', 'Warning')
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Switch-ToChinese }
}))
$buttons.Controls.Add((New-ActionButton -Name '4  RESTORE' -Description 'Restore the saved settings from backup' -Color ([System.Drawing.Color]::FromArgb(150, 80, 170)) -Action {
    $r = [System.Windows.Forms.MessageBox]::Show(
        'Restore settings from the backup file?',
        'Confirm - Restore', 'YesNo', 'Question')
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Restore-Settings }
}))
$buttons.Controls.Add((New-ActionButton -Name '6  CHECK COMPATIBILITY' -Description 'Read-only: show OS and cmdlet availability' -Color ([System.Drawing.Color]::FromArgb(90, 100, 115)) -Action { Show-Compatibility }))
$buttons.Controls.Add((New-ActionButton -Name 'EXIT' -Description 'Close the tool' -Color ([System.Drawing.Color]::FromArgb(170, 60, 60)) -Action { $form.Close() }))

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::White
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.WordWrap = $false
$script:LogBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Both
$script:LogBox.Margin = New-Object System.Windows.Forms.Padding(6, 8, 12, 12)

$content.Controls.Add($buttons, 0, 0)
$content.Controls.Add($script:LogBox, 1, 0)
$root.Controls.Add($content, 2, 0)

Append-Log 'Ready.' ([ConsoleColor]::DarkGreen)
Append-Log ''
Append-Log 'BUTTONS:' ([ConsoleColor]::DarkYellow)
Append-Log '  1 SAVE              - Back up language, keyboard, region and timezone.' ([ConsoleColor]::DarkGray)
Append-Log '  2 INSTALL CHINESE   - Install zh-CN language pack (needs internet).' ([ConsoleColor]::DarkGray)
Append-Log '  3 SWITCH TO CHINESE - China region + UTC+8 + Pinyin keyboard.' ([ConsoleColor]::DarkGray)
Append-Log '  4 RESTORE           - Restore the settings saved with button 1.' ([ConsoleColor]::DarkGray)
Append-Log '  6 COMPATIBILITY     - Read-only check of OS and available cmdlets.' ([ConsoleColor]::DarkGray)
Append-Log '  EXIT                - Close the application.' ([ConsoleColor]::DarkGray)
Append-Log ''
Append-Log 'Recommended order: 6 -> 1 -> 2 -> 3. Use 4 to go back.' ([ConsoleColor]::Cyan)
Append-Log 'After 3 or 4, Sign Out or Restart to apply changes.' ([ConsoleColor]::Yellow)
Append-Log ''
#endregion

$form.Add_Shown({ Update-Status })
[System.Windows.Forms.Application]::Run($form)
