# chart

A drawing surface that writes **Mermaid**. Sketch a box, type into it, pull an arrow to
the next box — the sheet projects to Mermaid continuously. Shape recognition is
geometric (no model, no training data); labels are typed, never handwritten.

Written entirely in AIML, like `aidoc` and `glbview`.

The contract is [`doc/spec/chart.md`](doc/spec/chart.md); this README is the practical
overview.

**Status: spec only.** No sources yet — the build and usage sections below describe the
intended shape, not something that runs today.

## The one rule worth knowing up front

The **sheet** (`*.chart.yaml`) is the document. Mermaid is a lossy export: it carries
colour and structure, but no coordinates, sizes or anchor sides. So editing always
changes the sheet, and the tool never reads its own Mermaid back (spec §2). A version
that treated the Mermaid as its document would lose the arrangement on every reopen.

## Build (planned)

`exodus-chart.json` names the toolchain as `$AIML` and `$AIML_VENV/lib`, never a path, so
the same config builds on a workstation and in CI (aiml spec/68 §3). The compiler builds it
itself — **no exodus, no Python** (spec/68 §7):

```bash
# once, from an aiml build tree
<aiml>/out/aiml/aiml venv <aiml>/out/venv

. <aiml>/out/venv/env                # sets AIML, AIML_VENV, PATH
cd <this repo>
aiml build -c exodus-chart.json      # produces ./chart
```

Or let a venv install it, which builds it with the compiler it will live next to:

```bash
aiml venv <venv> install chart --path <this repo>   # -> <venv>/bin/chart
```

Tests run in CI, not locally (see `.github/workflows/ci.yml`).

## CI secrets

The workflow pulls a prebuilt aiml venv from kontor, keyed by aiml's commit, and builds it
only when that commit is not there yet. Three repository secrets switch that on:

| Secret | What it is |
|---|---|
| `KONTOR_URL` | base URL of the kontor instance |
| `KONTOR_TOKEN` | kontor token; `reader` is enough to pull, `writer` also lets CI store a freshly built aiml |
| `KONTOR_CA` | PEM of the private CA that signed kontor's certificate |

Without them the run still works — it just builds aiml every time, which is the most
expensive step by far (LLVM 18). `Pymann/aiml` is public, so no GitHub token is needed.

## Use (planned)

```bash
chart --sheet sheets/login.chart.yaml --mermaid doc/login.mmd   # headless export
```

## What it leans on

| Need | Comes from |
|---|---|
| Mermaid id/label hygiene | the emitter patterns in `test/aidoc/src/charts.aiml` |
| Left action bar | glbview's panel — `ui.begin` / grid / cell / `ui.button` -> one `action` int, panel as a scrollable cell (`test/glbview/src/viewer.aiml`, its spec §4.3) |
| Typing in a shape | `text_input` prefab child — editable, multi-line, selection, clipboard, UTF-8 (aiml spec/44_6 §5e) |
| Sizing a node to its label | `engine.text_width(text, font_size)` / `engine.text_height(font_size)` (aiml spec/44_6 §5i) |
| Mermaid preview pane | `textbox` — read-only, scrollbar, `set_color_runs` for keywords (aiml spec/44_6 §5f) |
| Right-click menu | the `ui.spinbox` popup shield as the model for claiming input (aiml spec/44_3 §4.2) |
| Ink and edge drawing | `ui.draw_line` / `ui.draw_polyline` (aiml spec/44_3 §4.6) |
| Sheet (de)serialisation | `yaml.parse_file` + hand-written writer, same as aidoc |
| Building | `aiml build` (spec/68 §7) — exodus is only needed to build aiml itself |

## Stages

| Stage | Content | Rough effort |
|---|---|---|
| 0 | Sheet model, YAML load/save, Mermaid emitter, headless `--export`, stencil palette, typed labels | 2–3 days |
| 1 | Freehand recognition (§7.1–7.5) + straightening (§7.6) | 1–2 days |
| 2 | Right-click menu, colour -> `classDef`/`style`, groups -> `subgraph` | 1–2 days |
| 3 | Snap refinements, direction proposal, editor suite under Xvfb | 1 day |

Stage 0 is deliberately the whole tool minus freehand: it already produces correct
Mermaid, and everything after it only changes how shapes get onto the sheet.

## Tests

```bash
tests/run_tests.sh          # recogniser, straightening, emitter — all headless
```

The editor suite needs a display and runs **separately** (`Xvfb` + XTEST clicks). It is
kept out of the normal loop on purpose: a test that opens a window blocks until the
window closes, and `run_all_tests.sh` has no timeout, so one such test stops everything
behind it.
