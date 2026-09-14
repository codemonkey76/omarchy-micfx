# Changelog

What changed in each release of Mic FX, newest first. Each release is tagged
in git as `vX.Y.Z` and matches `version` in `manifest.json`.

## 1.1.0 — 2026-09-15

### Tone: sound less nasal or boxy

A new **TONE** stage between the noise gate and the compressor, off until you
switch it on:

- **Nasal cut**, a narrow dip for the honky "in your nose" sound, usually
  800 Hz – 1.5 kHz.
- **Boxiness cut**, a milder dip for boxy, muddy tone around 300 – 500 Hz.
- **Presence**, a gentle boost for clarity around 3 – 5 kHz.
- **Air**, a gentle high boost above 8 – 10 kHz.

It uses PipeWire's own filters, so there's nothing new to install. The README
explains how to find your own frequencies.

### Sample: tune by ear

**Record** ten seconds of yourself talking, then **Loop** it while you move the
sliders. Changes are heard straight away, and **Original** / **With settings**
flips between the recording and your settings. Listening to a recording works
far better than listening to yourself live. The loop plays through a private
copy of the chain, so a call using Mic FX isn't affected, and it stops when the
panel closes.

### A tidier panel

- Each stage is now one line with its switch and a summary of what it's doing,
  such as `−44 dB` or `nasal −5 dB @ 1.1 kHz`. Click a stage to open it.
- An open stage shows its everyday controls. **More** shows the rest (attack,
  release, frequencies, widths).
- An open stage that differs from its defaults has a reset icon that puts just
  that stage back. From the command line: `omarchy-mic-fx reset gate`.

## 1.0.0 — 2026-09-12

First release.

- A processed copy of your microphone that every app can use: input gain,
  high-pass, RNNoise noise suppression, noise gate, compressor and limiter.
- A bar icon and panel with an on/off switch, a microphone picker, and a
  section per stage with live sliders.
- A setup wizard that listens to your room, your voice and your typing,
  suggests settings, and lets you hear typing over talking before and after.
- The helper runs only programs it has checked in root-owned system
  directories, from a closed environment, with deadlines and output limits.
