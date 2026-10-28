# JBL QuantumENGINE fix: headset detected, but all settings are greyed out

**English** | [Русский](README.ru.md)

Unofficial fix for **JBL QuantumENGINE** on Windows when your wireless JBL Quantum headset (tested on **Quantum 360P**)
is detected and plays sound, but **every setting is greyed out / inactive**: you can't change the EQ, surround sound,
sidetone or auto power-off, and the app **never offers a firmware update**.

Typical symptoms:

- QuantumENGINE shows the headset, but all buttons and sliders are grey and can't be clicked.
- Sound and the game/chat dial work, only the app can't control the headset.
- The firmware version is shown as `0.0.0`, and there is no "Update firmware" button.
- Reinstalling QuantumENGINE, replugging the dongle or rebooting doesn't help.

## In short

The cause is **outdated dongle firmware**. The old firmware always answers QuantumENGINE that the headset is "not
connected", so QuantumENGINE locks everything, **including the firmware update that would fix it**.

This tool temporarily makes QuantumENGINE ignore that wrong answer, so you can update the firmware. After the update
you put the original file back, and everything works with the stock app.

1. **Install the patch** → settings become active.
2. **Update the firmware** from QuantumENGINE.
3. **Restore the original file** → done.

> [!IMPORTANT]
> This is an unofficial tool, not affiliated with JBL or Harman. You use it at your own risk.
> It doesn't contain any JBL files: it modifies `QuantumServer.dll` from **your own** QuantumENGINE install
> and keeps a backup of the original.

## Requirements

- Windows 10/11 (64-bit)
- **QuantumENGINE 2.8.6** (the patcher checks the version and refuses to patch an untested one)
- Headset charged to at least 50% (for the firmware update)
- Administrator rights

## Step-by-step

### 1. Download

1. Open the [**Releases**](../../releases/latest) page and download `QEWirelessFix-v*.zip`.
2. Right-click the zip → **Properties**. If there's an **Unblock** checkbox at the bottom, tick it and click **OK**.
3. Right-click the zip → **Extract All…**. You get a folder with `install.cmd`, `restore.cmd` and `QEWirelessFix.exe`.

### 2. Install the patch

1. **Close QuantumENGINE completely**, including the icon in the system tray (right-click → Exit).
2. Plug in the USB dongle and **turn the headset on**.
3. Right-click **`install.cmd`** → **Run as administrator**.
   - If Windows shows *"Windows protected your PC"*, click **More info** → **Run anyway**.
     This appears because the tool isn't code-signed; you can [build it yourself](#build-from-source).
4. Wait for the green **`Patch installed.`** message, then press any key.

### 3. Update the firmware

1. Open QuantumENGINE. The settings should now be active.
2. Open the headset page and start the **firmware update**. Follow the on-screen instructions:
   QuantumENGINE may ask you to connect the headset with a USB cable.
3. **During the update don't unplug the dongle, don't turn off the headset and don't close the app.**
4. When it finishes, **check again for an update**. In our case the first run updated only the headset and the
   second run updated the dongle. Repeat until QuantumENGINE says the firmware is up to date.

Example from our logs: chip versions `2.3.2 / 3.6.5` → `2.3.2 / 3.7.6` (first run) → `3.7.5 / 3.7.6` (second run).

### 4. Restore the original file

1. Close QuantumENGINE.
2. Right-click **`restore.cmd`** → **Run as administrator**.
3. Wait for **`Original QuantumServer.dll restored.`**
4. Open QuantumENGINE and check that the settings are still active and the EQ changes the sound.

Done! QuantumENGINE is back to stock, and future QuantumENGINE updates install normally.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `This QuantumServer.dll version was not tested` | You have a different QuantumENGINE version. Open an issue, or at your own risk: open **Command Prompt as administrator**, go to the extracted folder (`cd /d "<folder>"`) and run `install.cmd -Force`. |
| Settings are still grey after the patch | Make sure the headset is on, close and reopen QuantumENGINE. If it's still grey, open an issue and attach logs (see below). |
| No firmware update is offered | Wait about 15 seconds after opening QuantumENGINE (it checks JBL's server). Make sure the PC is online. |
| Settings are grey again after `restore.cmd` | The firmware is probably still old: install the patch again and repeat step 3. You can also keep the patch (QuantumENGINE updates will overwrite it). |
| EQ changes but you hear no difference | If the headset is connected by USB cable, unplug the cable so the sound goes through the dongle. |
| `Backup ... not found` | The original file was already restored, or the backup was deleted. Reinstalling QuantumENGINE always gives you the original file. |

### Collecting logs for an issue

The QuantumENGINE service writes its logs to `C:\Windows\SystemTemp\QuantumENGINE` (on older Windows 10:
`C:\Windows\Temp\QuantumENGINE`); only administrators can read them.
To copy them to `Documents\qe-logs`, run in an **administrator** PowerShell:

```powershell
$dst = "$env:USERPROFILE\Documents\qe-logs"; New-Item -ItemType Directory -Force $dst | Out-Null; foreach ($p in 'C:\Windows\SystemTemp\QuantumENGINE','C:\Windows\Temp\QuantumENGINE') { if (Test-Path $p) { Copy-Item "$p\*" $dst -Force } }
```

Also attach `%LOCALAPPDATA%\Temp\QuantumENGINE\QuantumClient.log`.
Logs contain your PC model and a device ID. Look through them before posting publicly.

## Which headsets can be affected

The patched code is shared by these QuantumENGINE product families: **Quantum 350, 360 / 360P / 360X / 360XB, 600, 610,
800, 810, 910 / 910P / 910X, Quantum TWS**.

**Only the Quantum 360P was tested.** If it worked (or didn't) for another model, please open an issue and say so.

## How it works (technical details)

QuantumENGINE has two parts: the window (`QuantumEngine.exe`) and a background Windows service
(`QuantumServer.exe`, service `QuantumService`) that talks to the dongle over USB HID.

1. For Quantum 360-series headsets the UI enables settings only if `WirelessConnected && Ready`
   (`Q360Series/ProductUI.cs`, `CheckDeviceEnable`).
2. `WirelessConnected` comes from the service, which asks the dongle HID feature report **`0x68`**
   ("is the headset connected over the air?") when the HID device opens, and afterwards listens for input report
   **`0x09`** (connection changed).
3. With old firmware, the dongle **always** answers `0x68 → 0x00` and never sends `0x09`, even while the headset is
   connected, the audio works and the game/chat dial reports `0x10xx` through the same HID channel:

   ```text
   [HIDV1] [Get    ] 0x6800      <- service restarted while the headset was connected
   [HIDV1] [Input  ] 0x1010      <- game/chat dial still reports through the dongle
   ```

4. Because of that, the service never runs its "headset connected" logic (reading firmware version, EQ, etc.), the app
   shows firmware `0.0.0`, and the firmware updater has nothing to compare, so it offers no update.

**The patch** adds one method to `QEService.Feature.MiscFeature+WirelessConnection+HIDV1` in `QuantumServer.dll`:

```csharp
protected override void OnHIDPropertyChanged(in byte value)
{
    byte connected = 1;
    base.OnHIDPropertyChanged(in connected);   // always report "connected"
}
```

Nothing else changes. With it, the service reads the real firmware version (`2.3.2 / 3.6.5`), QuantumENGINE finds the
newer firmware on JBL's server (`3.7.5 / 3.7.6`) and can install it. After the update the dongle reports the connection
on its own (`[Input] 0x0901`), so the patch is no longer needed.

### Tested files

| File | SHA-256 |
| --- | --- |
| `QuantumServer.dll` original (QuantumENGINE 2.8.6, file version 2.0.0.5) | `C6ED2A044934353ADB1819FFBBA5F25A6D37EC0D8B01CE4DBE34AF41007C6CD9` |
| `QuantumServer.dll` after the patch | `B014D2FEFC81875A6B27709280124333A4164FBFF5E64C32E2E98D8DE1720C9A` |

### Patcher command line

```text
QEWirelessFix check <QuantumServer.dll>
QEWirelessFix patch <QuantumServer.dll> <output.dll> [--force]
```

Exit codes: `0` ok, `1` usage/IO error, `2` already patched, `3` untested version (use `--force`), `4` not the expected file.

`install.ps1` and `restore.ps1` accept `-InstallDir <folder>` if QuantumENGINE isn't in `C:\Program Files\JBL\QuantumENGINE`.

## Build from source

Requires the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

```powershell
dotnet publish patcher -c Release -o dist
Copy-Item scripts\* dist
```

`dist` then contains the same files as the release zip. Releases are built by GitHub Actions from this source
(see `.github/workflows/release.yml`).

## License

[MIT](LICENSE) for the code in this repository. Uses [dnlib](https://github.com/0xd4d/dnlib) (MIT).

JBL, JBL Quantum and QuantumENGINE are trademarks of Harman International Industries. This project is not affiliated
with, endorsed or supported by JBL or Harman.
