# Display Flashing and Legacy Driver Crash Loops

## Purpose

This note records the August 2026 investigation into a repeating display or cursor flash seen while STM Desktop Listener was open. It explains the leading, high-confidence explanation, separates observed facts from inference, and defines a prevention policy that remains safe for people who legitimately use Wacom tablets, pen displays, calibration tools, accessibility software, audio drivers, or other creative hardware.

The important distinction is not "Wacom installed" versus "Wacom absent." A current, healthy, supported driver is valid. The failure condition is a third-party driver or helper that is incompatible, repeatedly crashes, and is immediately restarted by macOS.

## Incident summary

The Mac showed a brief display flash at a repeating cadence. The symptom appeared after screenshot-editor work, so the first suspicion was an STM screenshot overlay, editor window, retained WindowServer surface, or capture helper.

The investigation eventually identified an obsolete process:

- Executable: `PenTabletDriver`
- Bundle identifier: `com.wacom.pentablet`
- Installed path: `/Library/Application Support/Tablet/PenTabletDriver.app`
- Version: Wacom Tablet `5.3.7-6` (`5.3.7f6`)
- Architecture: Intel `x86_64`, translated through Rosetta on Apple silicon
- Parent: PID 1, which is consistent with a launchd-managed background service
- Investigation host: macOS 14.7.6 (23H626), Mac mini (Macmini9,1), Apple M1
- Hardware status: no Wacom device was connected or required on this Mac

The archived crash reports were created on this Mac on September 27, 2023, while it ran macOS 11.7.6. They name the same installed path, bundle, executable, and Wacom Tablet 5.3.7-6 version later identified during the August 2026 investigation. They prove that this installed driver had failed repeatedly before the investigation, but they do not prove that it was crashing on the current macOS release.

Those reports show crashes at 17:04:47, 17:04:51, 17:04:54, and 17:04:57. Successive `PenTabletDriver` processes failed with `EXC_BAD_ACCESS` and `SIGSEGV`; the changing process IDs and roughly three-second spacing are consistent with the service crashing and macOS launching it again.

The user authorized complete removal because the Wacom software was no longer needed. After the obsolete Wacom application, helpers, launch items, preferences, receipts, and related components were removed, the Mac was restarted. The restart mattered because deleting files does not guarantee that an already-loaded process, service registration, extension, or cached executable state has left memory.

## Controlled verification after restart

The following checks did not reproduce the flashing:

1. Leave STM Desktop Listener closed after login.
2. Launch STM Desktop Listener and leave it idle.
3. Take a plain region screenshot with Command-Shift-4.
4. Draw an arrow in the native screenshot editor.
5. Apply repeated `Shift-Plus` zoom until the original arrow moves outside the visible viewport.
6. Draw another arrow.
7. Resize the editor window.
8. Access Orca from a mobile device.

The tests also established these process boundaries:

- The two existing `stm-agent` processes were present before STM Desktop Listener launched. One was the expected RunAtLoad agent and one was the Brave native-messaging connection.
- STM Desktop Listener launched as one application process.
- Standard screenshot capture, selection, editor display, editor close, and editor deallocation stayed inside that application process.
- Plain and arrow screenshot tests did not start an STM screenshot helper or child process.
- No Wacom or `PenTabletDriver` process existed after the restart.

STM's login item was restored after the controlled test. Its production configuration remained mode `0600`, and the immutable production Worker URL was unchanged.

## What is proven and what remains inferred

### Proven

- Wacom Tablet 5.3.7-6 had produced repeated `EXC_BAD_ACCESS` crashes at an approximately three-second cadence.
- A live obsolete `PenTabletDriver` process was identified during the flashing investigation.
- The Wacom software was not required on this Mac.
- After the obsolete Wacom software was removed and the Mac restarted, the flashing was not reproduced during the controlled STM and screenshot-editor sequence.
- STM screenshots and editor actions did not create a new STM helper process.

### High-confidence conclusion

The obsolete Wacom driver crash loop is the most likely cause of the repeating flash. This conclusion is supported by the live process observation, historical crash reports at approximately the same cadence, and failure to reproduce after removal and restart. Because no abnormal exit of the current process or exact WindowServer or cursor-rendering event was captured during the August 2026 investigation, and removal plus restart changed more than one state variable, the evidence does not prove the precise visual mechanism or exclude every alternative cause.

### Not proven

The exact WindowServer operation that made the restart visible was not captured. High-frequency window inventories and pixel probes did not identify a normal application window responsible for the flash. A tablet driver can own input monitoring, cursor behavior, accessibility integration, background helpers, and low-level device communication. Restarting such a component can disturb display or cursor presentation outside the ordinary application-window model, but the precise rendering path remains an inference.

It was also not proven that STM's screenshot action launched or awakened the Wacom driver. The screenshot workflow uses a full-screen selection surface, so a pre-existing display disturbance was easier to notice and appeared causally related. After the Wacom service was gone, plain capture, annotation, zoom, editor resizing, and mobile Orca use all remained flash-free.

## Why this can happen with creative hardware

Tablet, pen-display, calibration, color-management, capture-card, virtual-camera, monitor-control, and remote-desktop packages often install more than a visible application. They may add:

- Login items and launchd agents or daemons
- Accessibility and Input Monitoring clients
- DriverKit system extensions or older kernel extensions
- Privileged helpers
- Cursor, display, USB, or HID services
- Background update and device-registration services

A visible application can be removed while one or more of those components remain. If a retained helper is incompatible with the current macOS version or Apple-silicon environment, launchd may keep restarting it after every crash. The visible symptom can then be attributed to whichever foreground application happens to use the screen at the time.

Apple advises updating or removing incompatible legacy system extensions through the developer. Wacom's macOS 14 guidance, consulted in August 2026, says that a supported device must use driver 6.4.4-* or newer. The incident driver was version 5.3.7-6, outside that documented combination, and was observed crashing under Rosetta. Intel translation alone is not evidence that a driver is defective; the repeated abnormal exits are the material signal.

## Safe prevention policy

STM Desktop Listener must not block, disable, kill, or uninstall software merely because it is made by Wacom, Adobe, a display vendor, or another creative-hardware vendor. That would break valid professional setups and would confuse installation with malfunction.

Use this policy instead:

1. Treat a current, stable driver as supported.
2. Warn only when there is evidence of incompatibility or repeated failure.
3. Prefer the vendor's current compatible driver and official uninstaller.
4. Never make an automatic destructive change.
5. Require a restart after driver removal or replacement.
6. Verify the original symptom from a clean login before blaming STM.

### Signals that justify a warning

A current crash-loop warning should require one of these corroborated evidence paths, not merely an installed vendor name or old version:

- Three or more crash reports from the preceding 24 hours for the same executable and version, with their timestamps falling within one minute; or
- A live trace showing repeated launches paired with abnormal exits for the same executable and version, attributed to the same launchd label when that label is observable.

Historical reports outside the 24-hour window may inform a compatibility notice but must not trigger a current crash-loop warning. Repeated starts without confirmed abnormal exits should remain informational until the component's expected lifecycle is known. An unsupported version, Intel translation, stale launchd registration, absent hardware, or missing permission may justify a compatibility notice, but none is sufficient on its own for a crash-loop warning. Version guidance must be checked against the exact macOS version, device model, and current vendor documentation.

A vendor name, an installed application, Accessibility permission, or Input Monitoring permission by itself is not an error.

## Recommended STM diagnostic feature

A future STM release can make this class of failure easier to diagnose without policing installed software. Add a user-initiated **Diagnose Screen Flashing** action under Permissions or Troubleshooting.

The diagnostic should:

1. Run only when the user requests it, for 15 to 30 seconds.
2. Record process births and exits with executable path, bundle identifier, version, architecture, parent process, and launchd label.
3. Group repeated launches by executable identity and calculate restart cadence.
4. Read metadata, not full contents, from recent user crash reports and group repeated crashes by executable.
5. Record STM's own capture backend and overlay/editor lifecycle timestamps.
6. Classify current healthy drivers as informational, not suspicious.
7. Produce a redacted report containing no credentials, transcription tokens, screenshot pixels, document names, typed text, or browser content.
8. Offer vendor-safe next actions: update, use the official uninstaller, restart, and retest.

The diagnostic must not:

- Run a permanent background process watcher.
- Upload installed-software inventories.
- Match broad names such as `Wacom`, `Adobe`, or `Photoshop` and declare them incompatible.
- Stop a service, unload an extension, delete files, or change permissions.
- Ask users to weaken macOS security settings as a generic fix.
- Claim that a process caused a flash based only on timing. It should report correlation; non-reproduction after an update or removal and restart strengthens the attribution but does not prove the precise visual mechanism.

### Suggested severity model

- **Healthy:** A supported driver is present with no restart or crash evidence. Take no action.
- **Compatibility notice:** An old or translated driver is present, but no crash loop is observed. Recommend checking vendor support.
- **Crash-loop warning:** Show only when one of the current-evidence thresholds above identifies the exact executable and version, repeated abnormal exits, and the launchd label when observable. Recommend the current vendor update or the official vendor uninstaller when the component is unused. Never stop, unload, disable, or remove it automatically.
- **Resolved:** The component was updated or removed, the Mac was restarted, and the controlled test matrix no longer reproduces the symptom. This status describes the observed outcome, not proof that every part of the causal mechanism is known.

## User runbook

When display flashing appears:

1. Record the time and approximate cadence. A regular interval often indicates a restarting service or scheduled helper.
2. Test for 60 seconds with STM closed. Do not assume that the foreground app owns a system-level flash.
3. Check Activity Monitor and `~/Library/Logs/DiagnosticReports` for the same third-party process repeatedly appearing or crashing.
4. Note the exact executable path, bundle identifier, version, architecture, parent process, and restart interval. Do not collect screenshot contents or credentials.
5. If the hardware is still used, check the vendor's compatibility list and install the current supported driver. Back up device preferences first.
6. If the hardware is no longer used, use the vendor's official uninstaller. Manual deletion is a last resort and requires explicit approval.
7. Restart the Mac. Logging out or deleting files is not an equivalent test.
8. Retest in this order: idle desktop, STM launch, plain capture, annotation, zoom, editor resize, then other suspected tools.
9. If the flash remains, repeat the process trace and investigate the next crash-looping or display-integrated component. Do not remove unrelated software in bulk.

For a required Wacom device, follow Wacom's official uninstall and reinstall procedure and install the driver version compatible with both the tablet model and the installed macOS release. Wacom warns that uninstalling removes preferences, so back them up before proceeding. If the device is no longer supported by a current driver, use Wacom support guidance rather than forcing a historical driver onto a production Mac.

## Documentation sources

- Apple Support: [If you get an alert about a system extension on Mac](https://support.apple.com/en-us/120363)
- Wacom, "Is there a driver for macOS 14 Sonoma?": <https://support.wacom.com/hc/en-us/articles/17629089706391-Is-there-a-driver-for-macOS-14-Sonoma>
- Wacom Support: [Uninstall and reinstall the Wacom driver on macOS](https://support.wacom.com/hc/en-us/articles/1500006264581-How-do-I-uninstall-and-re-install-the-Wacom-driver-on-Mac-OS-for-a-Pen-Tablet-Pen-Display-or-Pen-Computer)

## Closing rule

Do not diagnose creative-hardware software by brand. Diagnose it by compatibility, version, architecture, crash evidence, restart cadence, and controlled removal or update followed by a restart. If flashing returns, run the evidence checklist before changing STM or removing another driver.
