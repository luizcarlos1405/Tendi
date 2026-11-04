# Tendi

Live, local dictation for the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) shell on
[niri](https://github.com/YaLTeR/niri).

Press a key and talk. A small pill at the bottom of the screen shows your words as you say them, and
they keep getting corrected while you speak. When you stop, the text is pasted into the window you
were in. Speech is turned into text on your own machine with
[whisper.cpp](https://github.com/ggml-org/whisper.cpp); no audio or text leaves it.

> [!NOTE]
> Tendi works on the setup it was built on (NixOS, niri, an NVIDIA GPU), but it isn't ready for
> general use: whisper.cpp is its only speech engine, you install it by hand, and parts of it assume
> niri. It isn't in Noctalia's community plugins yet;
> [#1](https://github.com/luizcarlos1405/Tendi/issues/1) lists what's missing.

## What it does

- **Live text, corrected as you go.** About twice a second, whisper transcribes everything said so
  far again, so the text fixes itself as more context comes in. The pass that runs when you pause is
  the final, full-quality text, so the paste is instant.
- **Stops on its own.** Recording ends 2 s after you stop talking. Press the key again or click the
  mic to end it sooner; the lock button keeps it listening through pauses.
- **Pastes without taking over your clipboard.** The text is pasted rather than typed key by key, and
  the clipboard gets its old content back right after. The text is marked sensitive, so clipboard
  histories that respect that skip it (Noctalia's does).
- **Keeps a history.** Every transcription is saved before it's pasted, so nothing is lost when no
  text field had focus. A bar icon lists the latest ones (100 by default); click one to copy it.
- **Can skip pasting.** The keyboard button in the pill, or a setting, turns pasting off; the text
  then only goes to the history.

## Requirements

| What | Why | Notes |
| --- | --- | --- |
| [Noctalia](https://github.com/noctalia-dev/noctalia-shell) v5 with plugin API 30 or newer | the pill, the history panel, the settings | built on v5.0.1 |
| [niri](https://github.com/YaLTeR/niri) | telling terminals from other windows, since terminals paste with Ctrl+Shift+V | elsewhere terminals get Ctrl+V, see [Limits](#limits) |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp): `whisper-server` and `whisper-cli` | speech to text | the hard one, see below; built on 1.8.4 |
| a whisper model (ggml format) | | `large-v3-turbo` (1.6 GB) by default |
| [wl-clipboard](https://github.com/bugaevc/wl-clipboard) **2.3 or newer** | pasting, and restoring the clipboard | 2.3 (March 2026) added `wl-copy --sensitive`; with an older one every paste fails, though the text still reaches the history |
| [wtype](https://github.com/atx/wtype) | pressing the paste keys | needs the Wayland virtual-keyboard protocol, which niri, Hyprland and Sway have |
| ffmpeg with PulseAudio input | recording, and the level meter | works on PipeWire through pipewire-pulse |
| curl | talking to `whisper-server`, downloading models | |
| bash 5+, GNU coreutils, awk, sed, grep, diffutils, procps | the script itself | it uses GNU `dd` options, so BusyBox won't do |

### Getting whisper.cpp

Live text needs `whisper-server`, whisper.cpp's HTTP server, and a GPU build makes it fast enough.
Where it comes from:

| System | Package |
| --- | --- |
| NixOS / nixpkgs | `whisper-cpp`, `whisper-cpp-vulkan`, or `whisper-cpp.override { cudaSupport = true; }` for NVIDIA |
| Arch | `whisper-cpp`, plus one GPU backend: `ggml-cuda` (NVIDIA), `ggml-hip` (AMD) or `ggml-vulkan` (any) |
| Debian testing/unstable, Ubuntu 26.10+ | `whisper.cpp-tools`, plus `libggml0-backend-vulkan` for a GPU (there is no CUDA backend package) |
| Ubuntu 26.04 | `whisper.cpp`, plus `libggml0-backend-vulkan` for a GPU |
| Fedora | its `whisper-cpp` package only has the libraries, no `whisper-server`: build it |
| Debian stable, older Ubuntu, anything else | build it |

To build it (see [whisper.cpp's README](https://github.com/ggml-org/whisper.cpp#quick-start)):

```sh
git clone https://github.com/ggml-org/whisper.cpp && cd whisper.cpp
cmake -B build -DGGML_VULKAN=1   # -DGGML_CUDA=1 for NVIDIA's CUDA, neither for CPU only
cmake --build build -j --config Release
ln -s "$PWD/build/bin/whisper-server" "$PWD/build/bin/whisper-cli" ~/.local/bin/
```

### Hardware

On the NVIDIA laptop GPU it was built on (RTX PRO 1000 Blackwell), a live pass takes 0.35–0.6 s, and
`whisper-server` holds about 2 GB of VRAM while a dictation runs (none in between). AMD and Intel
GPUs should work through Vulkan, but haven't been tried. Without a GPU, pick a smaller model: the live
text then lags further behind, the final text takes longer and accuracy drops, mostly outside English.

| Model (`DICTATE_MODEL`) | Size |
| --- | --- |
| `large-v3-turbo` (default) | 1.6 GB |
| `large-v3-turbo-q5_0` | 574 MB |
| `small` | 488 MB |
| `base` | 148 MB |
| `tiny` | 78 MB |

## Install

Nothing installs it for you yet; put the pieces in place by hand:

1. **The scripts.** Copy `bin/dictate` and `bin/transcribe` to `~/.local/bin`. `dictate` does the
   dictation; `transcribe` is its fallback, and transcribes audio files on its own too
   (`transcribe -h`).
2. **The model.** Download it once:

   ```sh
   mkdir -p ~/.local/share/whisper
   curl -L -o ~/.local/share/whisper/ggml-large-v3-turbo.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
   ```

   The other models live at the same address under their own names (`ggml-small.bin`, ...).
3. **The plugin.** Copy `plugin/` to `~/.local/share/noctalia/plugins/dictation`, the folder Noctalia
   loads local plugins from, and enable it:

   ```sh
   noctalia msg plugins enable luiz/dictation
   ```

4. **The bar icon.** Add `luiz/dictation:bar` to a bar's widgets in `~/.config/noctalia/config.toml`,
   for example:

   ```toml
   [bar.default]
   end = ["tray", "luiz/dictation:bar", "battery"]
   ```

   If you have changed the bar in Noctalia's settings before, the list saved there, in
   `~/.local/state/noctalia/settings.toml`, replaces the one in `config.toml`, so add it there.
5. **A key.** In niri's `config.kdl`:

   ```kdl
   binds {
       Mod+Shift+D repeat=false hotkey-overlay-title="Dictate (press again to stop)" { spawn-sh "~/.local/bin/dictate"; }
   }
   ```

## Usage

Press the key and talk. Pause for 2 s, press the key again, or click the mic, and the text is pasted.
Say nothing for 8 s and it gives up.

| In the pill | Does | Same from a terminal |
| --- | --- | --- |
| mic | stop now and paste | `dictate` (a second time) or `dictate stop` |
| keyboard | pasting on or off for this dictation (off: history only) | `dictate type` |
| lock | keep listening through pauses until stopped | `dictate lock` |
| X | throw the recording away | `dictate cancel` |

The bar icon opens the history: click an entry to copy it, and the trash button clears it all
(click it twice). Right-click the icon for the settings.

## Settings

In Noctalia's plugin settings:

| Setting | Default |
| --- | --- |
| Transcriptions to keep | 100 (1–1000) |
| Type by default: start each dictation with pasting on | on |
| Lock by default: start each dictation locked | off |

The rest are environment variables for `dictate`, set in the keybinding, for example
`spawn-sh "DICTATE_LANG=pt ~/.local/bin/dictate"`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DICTATE_LANG` | `auto` | spoken language, as a whisper language code (`en`, `pt`, ...) |
| `DICTATE_MODEL` | `large-v3-turbo` | model, the name between `ggml-` and `.bin` |
| `DICTATE_SOURCE` | `default` | PulseAudio/PipeWire source to record; an audio file plays in real time instead, for testing |
| `DICTATE_SPEECH_DB` | `-42` | level in dBFS that counts as speech |
| `DICTATE_PAUSE` | `2` | seconds of silence that end the dictation |
| `DICTATE_WAIT` | `8` | seconds to wait for speech before giving up |
| `DICTATE_MAX` | `900` | longest recording, in seconds |
| `DICTATE_PORT` | 40000 + your UID mod 20000 | localhost port for `whisper-server` |

## Limits

- **whisper.cpp is the only engine.** There is no other local engine and no cloud API.
- **Terminals are only recognized on niri.** `dictate` asks niri which window has focus, so that
  terminals get Ctrl+Shift+V. On other compositors every window gets Ctrl+V, which most terminals
  don't paste with. The list of terminals is fixed in the script: kitty, Alacritty, foot, Ghostty,
  WezTerm, Konsole, COSMIC Terminal, GNOME's terminals and xterm.
- **Pasting means Ctrl+V.** An app with another paste shortcut (Vim in normal mode, for one) gets the
  wrong keys. The text is still in the history.
- **The clipboard comes back in one format.** Copied files, plain text or an image are restored, but
  rich text loses its formatting. The restore runs 0.5 s after the paste keys, so an app slower than
  that to read the clipboard pastes the old content instead.
- **Clipboard managers that ignore the sensitive hint** (`x-kde-passwordManagerHint`) may still save
  each dictation to their history.
- **The first words take a moment to show.** `whisper-server` starts with each dictation, so the
  model doesn't sit in VRAM the rest of the time, and loading it takes 1–2 s. Recording starts at
  once, so nothing you say is lost; only the preview starts late.
- **No live text without the model or `whisper-server`.** `dictate` then transcribes the whole
  recording at the end with `transcribe`, which is slower. And if the model is missing, `transcribe`
  first downloads it (1.6 GB), in the middle of your dictation.
- **Long dictations get split.** Whisper handles 30 s of audio at once, so past 20 s the text up to
  a pause becomes final and later passes only work on what came after it. With no pause at all in
  28 s, the cut goes at the quietest moment, which can split a word.
- **Whisper can invent words in noise**, like a "Thank you." out of near-silence; tune
  `DICTATE_SPEECH_DB` to your microphone if it happens. Detecting the language can misfire on very
  short phrases; set `DICTATE_LANG` if you dictate in one language.
- **The history is plain text.** Everything you dictate stays in `~/.local/state/dictate/history.jsonl`
  (readable by your user only) until it's pushed out or you clear it.
- **Tested on one machine only:** NixOS, niri, Noctalia v5.0.1, whisper.cpp 1.8.4 with CUDA, kitty
  and GTK apps.

## What it touches

- **Network:** `127.0.0.1` only, to talk to its own `whisper-server`. `transcribe` downloads a model
  from Hugging Face when it's missing.
- **Files:** `$XDG_RUNTIME_DIR/dictate/` while a dictation runs (removed at the end);
  `~/.local/state/dictate/` for `history.jsonl` and the `settings` the plugin writes for the script;
  models in `~/.local/share/whisper/`.
- **Programs it runs:** `whisper-server`, `ffmpeg`, `curl`, `wl-copy`/`wl-paste`, `wtype`,
  `niri msg` and `noctalia msg`.

## How it works

`dictate` does the work and the plugin shows it. They only share files:

- `dictate` records with ffmpeg (raw 16 kHz audio, plus a level reading every 100 ms), starts
  `whisper-server`, and transcribes the audio again and again, writing the newest text to
  `$XDG_RUNTIME_DIR/dictate/live`. It opens and closes the pill with `noctalia msg panel-open`/`panel-close`.
- The pill reads those files to draw the text and the meter, and its buttons create the `stop`,
  `cancel`, `lock` and `type` files the script watches.
- The plugin's service writes the settings to `~/.local/state/dictate/settings` for the script, and the
  history panel lists `~/.local/state/dictate/history.jsonl`.

Inside, it still has its first names: the command is `dictate`, and the Noctalia plugin is
`luiz/dictation`, shown as "Dictation".

## License

[MIT](LICENSE)
