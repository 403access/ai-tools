---
title: Voice input
sidebar_position: 6
---

# Voice input

Both apps can turn speech into an editable prompt.

## Where it works

- The **conversation composer** in a session's Chat tab.
- The **first message** field in the new-session sheet, on macOS and iOS.

Tap the microphone to start dictating. While listening, the button turns red.
Tap it again to stop.

## What happens to your text

- Dictation appends to whatever you already typed; it does not replace the
  existing draft.
- The transcript stays editable, so you can fix names, code, or punctuation
  before sending.
- Sending is still an explicit action. Dictation never submits a prompt by
  itself.

## Permissions

The first use asks for:

- **Microphone** access.
- **Speech Recognition** access.

If either is denied, allow it in the system or app settings and try again.
On macOS, check **System Settings → Privacy & Security → Microphone** and
**Speech Recognition**. On iOS, check the OpenCodeBar entry in Settings.

## On-device recognition

Speech recognition runs on the device when the current language supports it.
Otherwise the system speech service may process the audio. OpenCodeBar does not
send the audio to its own servers; there are no OpenCodeBar servers.

## Availability

The feature uses the system speech framework. It requires a supported language
package and an available recognizer. If recognition is unavailable, the app
shows an error instead of silently doing nothing.
