---
title: Voice input
sidebar_position: 6
---

# Voice input

Both apps can turn speech into an editable prompt, using a speech model that
runs on the device.

## Where it works

- The **conversation composer** in a session's Chat tab.
- The **first message** field in the new-session sheet, on macOS and iOS.

Tap the microphone to start dictating. While listening, the button turns red.
Tap it again to stop.

## The first time you dictate

Dictation uses NVIDIA's Parakeet model through
[FluidAudio](https://github.com/FluidInference/FluidAudio), which runs on the
Apple Neural Engine. The model is not shipped inside the app, so the first tap
downloads it once — about 450 MB — and compiles it for your Mac or iPhone. The
microphone button shows a progress ring while that happens; it takes roughly a
minute on a fast connection and does not repeat.

After that, dictation works offline. English systems use the English-only
model, which has the best recall; other languages use the multilingual model.

If the model cannot be prepared — no network on the very first use, or a
download that fails — the app falls back to the system speech recognizer so the
microphone still works. The Developer log in Settings records the fallback.

## What happens to your text

- Dictation appends to whatever you already typed; it does not replace the
  existing draft.
- The transcript stays editable, so you can fix names, code, or punctuation
  before sending.
- Sending is still an explicit action. Dictation never submits a prompt by
  itself.

## Permissions

The first use asks for **Microphone** access. **Speech Recognition** access is
requested only when the app falls back to the system recognizer.

If either is denied, allow it in the system or app settings and try again.
On macOS, check **System Settings → Privacy & Security → Microphone** and
**Speech Recognition**. On iOS, check the OpenCodeBar entry in Settings.

## Where audio goes

Nowhere. The audio is transcribed on the device and discarded; the app has no
servers to send it to. The only network use is the one-time model download.

## Disk space

The model lives in `~/Library/Application Support/OpenCodeBar/Models` on the Mac
and in the app's Application Support folder on iOS. It is unloaded from memory
after a few idle minutes but stays on disk, so the next dictation is instant.
Deleting that folder reclaims the space and triggers a fresh download on the
next tap.
