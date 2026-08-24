# LLM install instructions for STM Desktop Listener

Give the following prompt to an LLM or coding agent that has terminal access on your Mac.

## Prompt to paste

```text
You are helping me install STM Desktop Listener for Mac.

Goal: install the app into /Applications, install the native messaging host, open the app, and help me import credentials.

Context:
- STM Desktop Listener is a macOS menu bar app.
- It provides global screenshot, OCR, dictation, text transformer, color picker, pixel measurement, image optimizer, and Finder path copy actions.
- It is separate from STM Transcriber and must not overwrite it.
- It needs macOS 12.3 or newer.
- Dictation needs a credentials JSON with `workerUrl` and `authToken`. The `authToken` value must match the Worker's `JITSI_TRANSCRIBE_AUTH_TOKEN`, not its main `AUTH_TOKEN`.

Please do the following:

1. Locate the STM Desktop Listener folder, ZIP, or DMG I provide.
2. If I provided a ZIP, unzip it.
3. If I provided a DMG, mount it.
4. Prefer running the included install.command.
5. If install.command is not available, copy "STM Desktop Listener.app" to "/Applications/STM Desktop Listener.app" manually.
6. Install the native messaging host by running install-native-host.sh if it is available.
7. Remove quarantine from the installed app while preserving its existing signature:
   xattr -dr com.apple.quarantine "/Applications/STM Desktop Listener.app" || true
8. Do not re-sign the app unless macOS refuses to launch it. Re-signing can create new TCC permission entries.
9. Open it:
   open "/Applications/STM Desktop Listener.app"
10. Open the menu bar item and choose Import Credentials. Use the built-in Cloudflare Worker guide if I do not already have the immutable production workerUrl and transcription authToken.
11. Help me create a credentials JSON in this format, using values I provide:
   {
     "workerUrl": "https://share.seo-time-machines.workers.dev",
     "authToken": "MY_JITSI_TRANSCRIBE_AUTH_TOKEN",
     "cloudflareAccountId": "MY_CF_ACCOUNT_ID",
     "cloudflareApiToken": "MY_CF_API_TOKEN_WITH_WORKERS_AI_READ",
     "extensionId": "MY_STM_EXTENSION_ID",
     "browserBundleId": "com.brave.Browser"
   }
12. Tell me to click Choose JSON in the guide, select the JSON, then test dictation.
13. Tell me that screenshot, OCR, color picker, and measurement require Screen Recording permission.
14. Tell me that dictation requires Microphone permission.
15. Tell me that autopaste and selected text fallback require Accessibility permission.
16. If Screen Recording is not listed, run:
   '/Applications/STM Desktop Listener.app/Contents/MacOS/STM Desktop Listener' --request-screen-permission --open-screen-settings

Do not ask me to install Xcode or Swift unless you cannot find a prebuilt STM Desktop Listener.app. If source code is the only thing available, run ./install.sh from the project folder. If swiftc is missing, ask me to run xcode-select --install.
```

## Useful terminal commands

If installing from a packaged folder:

```bash
cd /path/to/STM-Desktop-Listener-Mac
./install.command
```

If installing manually from a packaged folder:

```bash
osascript -e 'quit app "STM Desktop Listener"' >/dev/null 2>&1 || true
rm -rf "/Applications/STM Desktop Listener.app"
cp -R "STM Desktop Listener.app" "/Applications/STM Desktop Listener.app"
xattr -dr com.apple.quarantine "/Applications/STM Desktop Listener.app" || true
./install-native-host.sh || true
open "/Applications/STM Desktop Listener.app"
```

If building from source:

```bash
cd /path/to/STM-Desktop-Listener
./install.sh
```

If creating a shareable package from source:

```bash
cd /path/to/STM-Desktop-Listener
./package.sh
```
