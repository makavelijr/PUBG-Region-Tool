# MakaveliJR PUBG Region Tool

![PUBG Region Tool](PUBG-Region-Tool-main.png)

PowerShell utility for Windows 10/11 that backs up and restores regional settings commonly used when switching regions for games such as PUBG.

## Features

- Automatic Administrator elevation
- Save current Windows regional settings to a backup file
- Restore saved settings
- Time zone handling
- UI language handling
- System locale handling
- User language list backup/restore
- Keyboard layout backup/restore

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Administrator privileges

## Usage

1. Right-click PowerShell and choose **Run as Administrator** (or allow elevation when prompted).
2. Run:

```powershell
./MakaveliJR-PUBG-Region-Tool.ps1
```

3. Follow the on-screen menu/options.

## Backup Location

The script stores backups in:

```text
%USERPROFILE%\MakaveliJR_backup.json
```

## Disclaimer

Use at your own risk. Review the script before running it and ensure you understand any changes it makes to Windows regional, language, and keyboard settings.

## Author

MakaveliJR


## GUI version (v2.0)

A Windows Forms interface is available as `MakaveliJR-RegionTool-GUI.ps1`.

| Button | Action |
| --- | --- |
| `6 COMPATIBILITY` | Read-only check of OS build and cmdlet availability. Run first on a new PC. |
| `1 SAVE` | Back up language, keyboard, region and timezone. |
| `2 INSTALL CHINESE` | Install the zh-CN language pack (needs internet). |
| `3 SWITCH TO CHINESE` | China region, UTC+8 timezone and Pinyin keyboard. |
| `4 RESTORE` | Restore the settings saved with `1 SAVE`. |
| `EXIT` | Close the application. |

Recommended order: `6` -> `1` -> `2` -> `3`. Use `4` to go back. After `3` or `4`, sign out or restart to apply changes.