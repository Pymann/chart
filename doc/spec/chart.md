# chart — Drawing Specification

`chart` is a drawing surface whose document **is** a diagram. You sketch a box, type
into it, pull an arrow to the next box, and the tool writes Mermaid. Shape recognition
is geometric, not learned. Label text is **typed**, never handwritten.

Written entirely in AIML. Mermaid emission reuses the proven id/label hygiene of
`aidoc` (`test/aidoc/src/charts.aiml`).

---

## 1. Goal

One surface, three jobs:

1. **Draw** — freehand strokes become clean primitives (rect, rounded, diamond,
   circle, hexagon, arrow) the moment the stroke ends (§7).
2. **Label** — click a shape, type into it. A real editable field, not a guess (§6).
3. **Export** — the sheet projects to Mermaid, continuously previewed and writable
   to a `.mmd` file (§5).

### 1.1 Non-goals (v1, normative)

| Not in v1 | Why / what instead |
|---|---|
| Handwriting recognition | Labels are typed (§6). The feature is not deferred for cost reasons alone — a typed label is *exactly* right, a recognised one is 90% right, and a diagram with a wrong word in it is worse than no diagram. |
| Mermaid **import** | Export is one-way (§2). A best-effort importer may come later; it can never be the document path. |
| Nesting beyond one level in a sequence (`alt` inside `loop` inside `opt`) | Blocks are a flat list of open/close steps (§5.8.3). Deeper nesting is readable but not offered by the editor in v1. |
| Auto-layout | Positions belong to the user. Mermaid re-lays out on render, and that is accepted (§5.7). |

---

## 2. The sheet is canonical; Mermaid is a projection

**Normative.** The editable document is a `*.chart.yaml` sheet (§4). Mermaid is
produced *from* the sheet and is **lossy**. Therefore:

- Every edit changes the **sheet**. Nothing ever edits the Mermaid text.
- Export is a **pure function** of the sheet: same sheet in, same bytes out.
- The tool **never** reads its own Mermaid output back as the source of truth.

The reason this rule is first, and not an implementation note: as soon as colour,
grouping and geometry became element properties (§3), Mermaid stopped being able to
hold the whole document. `style`/`classDef` carry colour; nothing carries coordinates,
sizes or anchor sides. A tool that treated its Mermaid as its document would lose the
drawing on every reopen — silently, and only for the user who had arranged it
carefully.

---

## 3. Document model

### 3.1 Models

```aiml
- model:
    name: Sheet
    description: "One slide: a drawing, and the canonical document for it (spec §2)"
    fields:
      - [dtype, DiagramType, flowchart]   # only `flowchart` emits in v1
      - [dir, Direction, TD]
      - [title, string, ""]            # slide heading; the `# ` of the Markdown export (§13)
      - [notes, string, ""]            # speaker notes: presenter only, never on the slide (§14)
      - [nodes, list<Node>]
      - [edges, list<Edge>]
      - [groups, list<Group>]
      - [steps, list<Step>]            # sequence only (§5.8.3): ORDER is the document
      - [next_id, i32, 1]              # monotonic; never reused, so ids stay stable (§5.1)

- model:
    name: Node
    fields:
      - [ident, string, ""]            # "n7"; stable for the sheet's lifetime
      - [kind, NodeKind, NodeKind.rect]
      - [pos_x, f32, 0.0]              # design coords, top-left anchor
      - [pos_y, f32, 0.0]
      - [width, f32, 120.0]
      - [height, f32, 60.0]
      - [text, string, ""]             # may contain "\n"; the caption of an image (§12)
      - [rows, list<string>]           # class compartments (§5.8.2); empty for every other type
      - [src, string, ""]              # image file, relative to the deck (§12); "" for every other kind
      - [fill, i32, 0]                 # 0xRRGGBBAA; 0 = inherit theme (§5.6)
      - [stroke, i32, 0]
      - [group, string, ""]            # owning Group.ident, "" = top level

- model:
    name: Edge
    fields:
      - [ident, string, ""]
      - [from_id, string, ""]          # Node.id
      - [to_id, string, ""]
      - [kind, EdgeKind, arrow]
      - [text, string, ""]             # edge label, "" = none
      - [rel, RelKind, plain]          # what the connector MEANS (§5.8.2); flowchart ignores it
      - [from_text, string, ""]        # end labels: multiplicities in a class diagram
      - [to_text, string, ""]
      - [stroke, i32, 0]

- model:
    name: Step
    description: "One line of a sequence diagram (§5.8.3). The list order IS the time."
    fields:
      - [ident, string, ""]
      - [kind, StepKind, message]
      - [from_id, string, ""]          # participant Node.ident
      - [to_id, string, ""]
      - [text, string, ""]             # the message, the note, or the block's condition
      - [line, LineStyle, solid]       # solid `->>`, dotted `-->>`
      - [head, EndCap, arrow]          # arrow `->>`, none `->`, cross `-x`
      - [word, string, ""]             # block keyword: loop / alt / else / opt / par

- model:
    name: Group
    fields:
      - [ident, string, ""]
      - [title, string, ""]
      - [parent, string, ""]           # nesting; "" = top level

**Field names, not YAML keys.** A model field must be at least three characters
(aiml spec/49 §23), hence `ident`/`pos_x`/`width`/`height`. The YAML keys stay short —
`id`, `x`, `y`, `w`, `h` (§4) — because a sheet is hand-edited and the check is on the
model, not on the file. Only the (de)serialiser knows both spellings.
```

### 3.2 Vocabularies

These words cross a file boundary (§4) — the sheet on disk names them and a later
build reads them back. They are therefore `wire: true` (spec/49 §18.2a): the members
*are* the contract, so an unused one must not warn. A new member is **appended**, never
inserted: the position is the value on disk.

`actor` is a stick figure. Mermaid has **no** use-case diagram; people draw one as a
flowchart, with a figure for the actor, an ellipse for the use case and a `subgraph` for
the system boundary. chart carries the figure as a shape of its own and exports it to
Mermaid as a `stadium` (§5.7) -- there is nothing closer, and a drawn actor must not
vanish on export.

`NodeKind.terminal` is the filled dot a state diagram starts and ends with. It is one
kind, not two: Mermaid writes `[*]` for both, and which one it is follows from the
direction of the edge touching it (§5.8.1). A document that stored "start" and "end"
separately could contradict itself; this one cannot.

`NodeKind.text` is the odd one and is listed last for that reason. It is **prose on the
slide**, not a box in the graph: drawn with no frame and no fill, left-aligned, and
skipped by the Mermaid projection (§5.7) because Mermaid has no frameless text. It
exists so a Markdown file can be read in whole (§18.4) instead of only its diagrams.

```aiml
- enum:
    name: NodeKind
    wire: true
    values: [rect, round, stadium, circle, diamond, hexagon, cylinder, subroutine, image, text,
             asymmetric, trapezoid, trapezoid_alt, parallelogram, parallelogram_alt, double_circle, actor,
             terminal]

# What a connector MEANS, as opposed to what it looks like (§5.8.2).  A class diagram
# distinguishes six; a flowchart has one and ignores the field.
- enum:
    name: RelKind
    wire: true
    values: [plain, inherit, compose, aggregate, depend, realize]

# One line of a sequence (§5.8.3).
- enum:
    name: StepKind
    wire: true
    values: [message, note, block_open, block_close]

# An edge is TWO independent things, and one enum for both was a modelling error:
# "dotted" and "bidirectional" are not alternatives -- `<-.->` is both at once, and
# `--o` could not be written down at all.
- enum:
    name: LineStyle
    wire: true
    values: [solid, dotted, thick, invisible]

- enum:
    name: EndCap
    wire: true
    values: [none, arrow, circle, cross, hollow]

# Kept only for READING sheets written before the split (§4.1a).  Never written.
- enum:
    name: EdgeKind
    wire: true
    values: [arrow, open, dotted, thick, bidirectional, invisible]

# `class_diagram`, not `class`: `class` is taken by the language (aiml spec/49), and a
# wire word must be spellable as a member.  The YAML on disk says `class_diagram` too --
# one spelling, not two.
- enum:
    name: DiagramType
    wire: true
    values: [flowchart, sequence, state, class_diagram]

- enum:
    name: Direction
    wire: true
    values: [TD, LR, BT, RL]
```

**Normative.** The model fields carry the **enum type**, not a string (§3.1). Only the
YAML (de)serialiser converts, and only there may a member name appear as text. Note that
`enums.value` takes a *literal* member (aiml spec/14), so string-to-enum is an explicit
mapping in the loader, not reflection — and an unknown word is therefore reported rather
than silently mapped to member 0. `static_off` is not to be used to silence a finding about them
(see memory: static checks are findings, not formalities).

---

## 4. Native format

A sheet is YAML, read with `yaml.parse_file` and written by hand — the same stack
`aidoc` uses, no extra runtime.

```yaml
dtype: flowchart
dir: TD
next_id: 5
groups:
  - { id: g1, title: "Auth", parent: "" }
nodes:
  - { id: n1, kind: stadium, x: 40,  y: 40,  w: 140, h: 56, text: "Start" }
  - { id: n2, kind: diamond, x: 40,  y: 160, w: 160, h: 90, text: "valid?", group: g1, fill: 0x2E4A7AFF }
  - { id: n3, kind: rect,    x: 260, y: 170, w: 140, h: 60, text: "Session\nanlegen" }
edges:
  - { id: e1, from_id: n1, to_id: n2, line: solid, head: arrow }
  - { id: e2, from_id: n2, to_id: n3, line: dotted, head: arrow, tail: circle, text: "ja" }
```

`line` defaults to `solid`, `head` to `arrow`, `tail` to `none`, so the common edge
writes two short words and the unusual one says what it is.

### 4.0a The writer never writes what the reader refuses (normative)

An edge needs both `from_id` and `to_id`.  The reader **rejects** a file whose edge is
missing one -- it has no Mermaid form (it would emit a bare `-->`), and dropping it
quietly loses a line the author drew.  The writer therefore refuses it too, with a
message naming the edge, rather than producing a file that the next open rejects.  A
format where saving can create an unloadable file is worse than one that complains at
the moment the damage is made.

### 4.1a Edges written before the split (normative)

A sheet may carry the old single `kind:` instead of `line`/`head`/`tail`. It is **read**
and mapped (`arrow` → solid+arrow, `open` → solid+none, `dotted` → dotted+arrow, `thick`
→ thick+arrow, `bidirectional` → solid+arrow+arrow, `invisible` → invisible+none), and
it is **never written back**. Both spellings in one edge is an error, not a merge: the
file would be saying two things and chart must not pick one.

Sheets on disk are documents (§2), and a tool that stops opening its own older files
teaches people not to trust it with their work.

**Normative.** An unknown `kind` on load is **not** silently defaulted: the loader
reports the file, the element id and the unknown word, and loads the sheet with that
element marked invalid. A sheet that lost a shape without saying so would be the same
class of failure as §2.

---

## 5. Mermaid projection

### 5.1 Ids

`Node.id` is already identifier-safe (`n` + integer) and emitted verbatim. Ids come
from `Sheet.next_id` and are **never reused** after a delete, so a diff between two
exports stays readable.

### 5.2 Node shapes

| `NodeKind` | Mermaid |
|---|---|
| `rect` | `n1["text"]` |
| `round` | `n1("text")` |
| `stadium` | `n1(["text"])` |
| `circle` | `n1(("text"))` |
| `diamond` | `n1{"text"}` |
| `hexagon` | `n1{{"text"}}` |
| `cylinder` | `n1[("text")]` |
| `subroutine` | `n1[["text"]]` |
| `asymmetric` | `n1>"text"]` |
| `trapezoid` | `n1[/"text"\]` |
| `trapezoid_alt` | `n1[\"text"/]` |
| `parallelogram` | `n1[/"text"/]` |
| `parallelogram_alt` | `n1[\"text"\]` |
| `double_circle` | `n1((("text")))` |
| `actor` | `n1(["text"])` — a stadium, §5.7: Mermaid has no actor |
| `text` | — not projected at all (§5.7) |

Labels are always quoted and escaped: `"` → `#quot;`, newline → `<br/>`. Quoting
unconditionally avoids the whole class of bugs where a label containing `(`, `[` or
`-` reshapes the node.

### 5.3 Edges

An edge carries a **line** and a **cap at each end**, and the Mermaid connector is
composed from the three rather than looked up as a whole:

| `line` | body | with an arrow head |
|---|---|---|
| `solid` | `---` | `-->` |
| `dotted` | `-.-` | `-.->` |
| `thick` | `===` | `==>` |
| `invisible` | `~~~` | `~~~` (caps dropped) |

| `head` / `tail` | at the head | at the tail |
|---|---|---|
| `none` | nothing | nothing |
| `arrow` | `>` | `<` |
| `circle` | `o` | `o` |
| `cross` | `x` | `x` |
| `hollow` | **not expressible** (§5.7) | not expressible |

So `line: dotted, head: arrow, tail: arrow` is `<-.->`, and `line: solid, head: circle,
tail: circle` is `o--o`. A label always uses the pipe form.

**Mermaid cannot mix caps.** `o--x` is not valid Mermaid; a mixed pair is exported with
the head's cap on both ends and reported once, because an export that silently flips one
end would draw a different diagram than the sheet shows.

On the canvas an edge kind is **visible**: `dotted` draws as dashes, `thick` with a
heavier line, `invisible` is not drawn at all (it still orders the Mermaid layout). An
editor where every arrow looks the same would make the author read the file to see what
they drew.

The pipe form carries the label, not the `-- text -->` form, so that **one** quoting rule
covers every label in the file (§5.2). With the inline form a label containing `-` or `>`
reshapes the arrow itself, and the failure is a changed diagram rather than an error.

### 5.4 Direction

`flowchart ${dir}` on the first line. The editor can **propose** a direction from the
layout (dominant arrow axis: more |dy| than |dx| over all edges → `TD`, else `LR`), but
the proposal only ever writes `Sheet.dir` through an explicit user action (§8) — never
on export, because an export that changes the document violates §2.

### 5.5 Groups

Each `Group` becomes a `subgraph`, nested per `Group.parent`:

```
subgraph g1 ["Auth"]
  n2
end
```

A node is emitted **inside** its group's block and nowhere else. Edges are always
emitted after all groups, at top level — Mermaid resolves them by id, and keeping them
out of the blocks avoids accidentally pulling an endpoint into a subgraph.

### 5.5a Output order (normative)

Export is promised to be a pure function of the sheet (§2), so the order is fixed, not
incidental:

1. `flowchart <dir>`
2. `classDef` lines, by class index
3. `subgraph` blocks in sheet order, each with its member nodes and nested groups, `end`
4. node declarations of ungrouped nodes, in sheet order
5. edge lines, in sheet order
6. `style` lines for one-off colours, in node order

Every line after the header is indented by four spaces per nesting level. `classDef`
precedes its uses: Mermaid does not require it, but a file whose classes are declared
after the nodes that carry them reads as if the colour came from nowhere.

### 5.6 Colour

`fill`/`stroke` of `0` mean "inherit the theme" and emit nothing. Otherwise:

- Collect the distinct `(fill, stroke)` pairs over all nodes.
- A pair used by **two or more** nodes becomes a `classDef c1 fill:#...,stroke:#...`, and
  each member's declaration carries `:::c1` (`n2{"valid?"}:::c1`) — on the node line, so
  the colour is never read apart from the node it belongs to.
- A pair used **once** becomes an inline `style n2 fill:#...,stroke:#...`.

The alpha byte is dropped (Mermaid has no alpha in `style`); `0x...FF` is the normal
case. A non-opaque alpha is **reported once** on export as a warning, not silently
flattened.

### 5.6a Text: colour and decoration (normative)

A label is styled **as a whole**, never per character: `Node.deco` is a bitmask
(1 bold, 2 italic, 4 underlined) and `Node.ink` is the text colour, 0 meaning "read it
off the fill" as the canvas has always done. An `Edge` carries the same two fields for
its label. Per-character formatting is not offered, because the document would then
have to carry a rich-text run inside every label and Mermaid could not hold it.

**Mermaid has no specification** -- it has a grammar, a documentation site and a
renderer -- so what follows was read out of the renderer's source (`flowDb.ts`), not
out of a promise:

| in chart | in Mermaid |
|---|---|
| text colour | `classDef`/`style` with `color:#rrggbb`. In `addClass`, a style entry matching `/color/` is pushed to `textStyles` as well, and that is the path that reaches the label. |
| bold, italic | the **markdown string**: `n1["`<code>\`**fett** _kursiv_\`</code>`"]`, which the grammar accepts for node labels, edge labels and subgraph titles (`sanitizeNodeLabelType`). |
| underline | **nothing.** Markdown has no marker for it, and `text-decoration` does not match `/color/`, so it never reaches the label. It is a loss (§5.7). |

What chart must **not** do is write `classDef x font-weight:bold`: it would be bold here
and silently nothing there. A projection may lose something; it may not pretend.

### 5.7 What is lost (normative list)

- **The hollow cap.** Mermaid's flowchart has no hollow (UML generalisation) end. It is
  exported as a plain arrow and reported once. It exists in the sheet because a use-case
  or class drawing needs it, and chart's own formats (SVG, PPTX, HTML) carry it.
- **A mixed pair of caps** (§5.3): Mermaid writes one cap for both ends.
- **Prose.** A `text` node is slide text, and a flowchart has nowhere to put it. The
  Mermaid projection leaves it out rather than inventing a box around it, which would
  put a paragraph into the graph as a node that nobody drew. Markdown, SVG, PPTX and
  HTML all carry it.

- **Underlining** (§5.6a): Mermaid cannot express it. The sheet keeps it and the
  canvas, SVG, HTML and PPTX all draw it; the `.mmd` does not say it.
- **A sequence in PPTX** (§17.2): the PowerPoint export writes the participants, not
  the messages, notes or blocks -- it draws from the node layer, and a sequence's
  document is `steps`. Said here rather than left to be discovered: SVG and HTML carry
  the whole diagram.
- **What belongs to another type** (§5.8): a flowchart export drops `rows` (class
  compartments), `rel` and the end labels, and it drops `steps` entirely. They are not
  "lost" in the sense of being dropped on the floor -- a flowchart has no place for
  them -- but a sheet that carries both a flowchart and class compartments keeps them
  in the sheet and shows none of them in the `.mmd`.

`x`, `y`, `w`, `h`, alpha, anchor sides, group bounding boxes, `next_id`. This list is
the justification for §2 and must be kept current when the model grows.

### 5.8 The other three diagram types (normative)

`Sheet.dtype` was a field only `flowchart` honoured; the tool strip offered the same
seventeen shapes whatever it said. A shape palette that does not change with the type
is a promise the window does not keep, so each type now has its own vocabulary, its own
projection, and its own palette (§8.0).

What they share: one file format (§4), one id scheme (§5.1), one colour model (§5.6),
one rule that the sheet is canonical (§2). What differs is listed here, and the list is
exhaustive -- a type that needs a field no other type reads says so.

#### 5.8.1 `state` -> `stateDiagram-v2`

A state chart is a drawing: positions are stored, exactly as in a flowchart.

| offered | is |
|---|---|
| `round` | a state |
| `terminal` | `[*]`, start or end |
| `diamond` | a choice |
| `text` | prose on the slide -- **not** projected (§5.7), because a Mermaid state note needs a state to hang on and free-floating prose has none |
| a group | a composite state |

```
stateDiagram-v2
  direction TD
  state "Angemeldet" as n2
  [*] --> n2 : login
  n2 --> [*] : logout
```

- A `terminal` node is **never declared**; every edge touching one writes `[*]` where
  that node would stand. Which end it is follows from the edge's direction, so the
  document cannot contradict itself.
- A group becomes `state "Titel" as g1 { ... }` around its members (§5.5).
- The label of an edge is `: text`. A state transition has **one** arrow: line style
  and end caps are lost (§5.7).
- A `diamond` is written `state n3 <<choice>>` and carries no label, which is what a
  choice pseudo-state is.

#### 5.8.2 `class_diagram` -> `classDiagram`

Also a drawing, so positions are stored. A class node is a box with **compartments**:
`Node.text` is the name, `Node.rows` are the lines under the rule.

`Edge.rel` says what a connector *means*; `from_text`/`to_text` are the multiplicities:

The arrow is written **in the order it was drawn** -- `from OP to`, never swapped --
so the id on the left of the `.mmd` is the id the author started the drag on:

| `rel` | Mermaid | drag from ... to ... |
|---|---|---|
| `inherit` | `from --\|> to` | child to parent |
| `realize` | `from ..\|> to` | implementation to interface |
| `compose` | `from *-- to` | owner to part; the part dies with it |
| `aggregate` | `from o-- to` | holder to held; the held outlives it |
| `depend` | `from ..> to` | user to used |
| `plain` | `from --> to` | association |

```
classDiagram
  class n1["Konto"] {
    +betrag: f64
    +buchen(wert: f64)
  }
  n1 "1" *-- "0..*" n2 : hat
```

Mermaid accepts both spellings of every relation (`<|--` and `--|>`); chart writes the
one that keeps the author's direction, because a round trip (§18) must not mirror the
drawing.

- The label-in-brackets form needs Mermaid 10 or newer. It is used anyway: the
  alternative is to put the user's class name into an id, and §5.1 exists because ids
  have to stay stable while names change.
- An empty `rows` emits `class n1["Konto"]` on one line, without a block: an empty pair
  of braces renders as an empty compartment, which claims the class has no members
  rather than that none were written down.

#### 5.8.3 `sequence` -> `sequenceDiagram`

**Here geometry is derived, not stored**, and that is the one real break with §3. A
sequence diagram has no free positions: a participant's place is its column, a
message's place is its row, and both come from order. The sheet therefore carries
`Sheet.steps`, and **the list order is the time axis**.

- **Participants** are the sheet's nodes, taken in `pos_x` order. Kind `actor` emits
  `actor n1`, anything else `participant n1`.
- `pos_y`, `width` and `height` of a participant are **not meaningful**. The editor
  keeps writing them -- one file format, not two -- and the reader ignores them.
  Dragging a participant sideways reorders the columns; dragging it up and down does
  nothing, and the pointer says so (§15.1a).
- A **message** is `from ->> to : text`, with the arrow chosen by line and head:
  `->>` solid arrow, `-->>` dotted arrow, `->` solid without head, `-x` cross,
  `--x` dotted cross.
- A **note** with both ends is `Note over n1,n2: text`, with one end
  `Note right of n1: text`.
- A **block** is `block_open` with its keyword in `word` and its condition in `text`
  (`loop every minute`, `alt ok`, `else failed`, `opt`, `par`), and `block_close`
  writes `end`. Steps between them are indented one level. The editor offers one
  level of nesting (§1.1); a file with more is read and written unchanged.
- An unbalanced block is an **error at export**, named with the step, not a silently
  closed one: Mermaid would render something, and it would not be the author's
  diagram.

**Normative -- the connect gesture takes the whole lifeline.**  `Nachricht` starts and
ends on a participant's **column**: the head box, or any point on its lifeline below it.
The head box is 56 units tall at the top of a 720-unit page, while the arrow is drawn
between the lifelines -- a gesture that only accepted the box would miss exactly where
the user aims, and missing looks like a tool that does nothing.  Columns are 230 apart
and the band is the box width, 170, so the 60 units between two lifelines belong to
neither and no drag is claimed by the wrong participant.  Everywhere else a connect
gesture still needs a node (§15.1).



---

## 6. Typing into a shape

A node's label is edited **on the canvas**, by drawing the text and a caret and reading
the input event queue (aiml spec/44_0 §3): a `text` event carries one code point in
`char_`, a `key_down` carries `Backspace`, `Enter`, `Escape`.

**Why not the `text_input` prefab.** A prefab child is a real editor with selection and
clipboard, and for a form it is the right answer. It lives in **design coordinates**
though, which the engine scales to the window by `rel_scale` — while this canvas draws in
**window pixels** and applies its own slide scale on top (§15). Keeping a prefab in step
with a canvas that scales and re-centres means maintaining two coordinate systems that
must agree every frame, and the first disagreement puts the caret somewhere the glyphs are
not. Drawing the text where the node is costs one `ui.draw_text` and cannot drift.

What that costs is **work, not features**. Drawing the text here rather than in a prefab
does not forbid a caret or a selection; it means chart positions them itself, from the
same measurement it draws with. An earlier version of this section claimed the opposite
and called it a price worth paying — it was simply the part that had not been written
yet, and an editor where the caret cannot be moved is not finished.

**Normative — the caret is measured, never estimated.** The x of index `i` on a line is
`ui.measure_text(line[0..i])` with the font the line is drawn in (aiml spec/44_3 §4.1).
A caret placed by counting characters times an average width drifts from the glyphs, and
a caret that is not where the next letter lands is worse than none.

| Key | |
|---|---|
| any character | replaces the selection, otherwise inserts at the caret |
| `Left` / `Right` | move one character; `Ctrl` by word; `Shift` extends the selection |
| `Up` / `Down` | the same column on the line above or below |
| `Home` / `End` | start / end of the line; `Ctrl` for the whole label |
| `Backspace` / `Delete` | delete the selection, otherwise one character before / after |
| `Ctrl+A` | select the whole label |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | the **system** clipboard (aiml spec/44_0) |
| `Enter` | commits |
| `Shift+Enter` | newline inside the label |
| `Escape` | reverts to the value the field had on entry |

A click inside the label places the caret; dragging from there selects. A click anywhere
else commits what was typed, which is the rule a press already followed.

**Normative — one consumer for the keyboard, and modifiers are not keys.** While a label
is being edited the editor takes its keys from the **event queue only**, and the slide
navigation of §14 is not polled. `Shift` and `Ctrl` are the stated exception: they are
read by polling (`input.key_down`), because a modifier is a *state* that qualifies the
key that arrived, not an event of its own. Polling a state cannot double-fire; polling a
key can, and that is the bug the rule exists for. A key read both as an event and as a poll fires twice, and the symptom is a
`Backspace` that eats two characters or an arrow that skips a slide — a class of bug this
codebase has already paid for.

Editing starts when a node is placed (§15.1), on `Enter` with a node selected, or on a
double click.

**Auto-grow.** The node grows to fit its label, measured rather than estimated:
`ui.measure_text` per line, widest line wins, `ui.text_height` times the line count for
the height (aiml spec/44_3 §4.1). Measuring and drawing from the same two numbers is what
keeps the box around the text.

### 6.1 The Mermaid pane

The live Mermaid preview is a **`textbox`** child: read-only, wraps, has a native
scrollbar and mouse-wheel scrolling, supports selection and `Ctrl+C`, and takes
`set_color_runs` for keyword colouring (spec/44_6 §5f, §5g). Read-only is the right
choice here and not a limitation — per §2 the pane is a view, so an editable one would
be a lie.

---

## 7. Stroke recognition

### 7.1 It is a pure function

**Normative.**

```
recognize(points: list<vec2>) -> list<string>   # NodeKind/EdgeKind members, best first
```

No engine state, no frame, no window. This is what makes the recogniser testable
headless (§9) — strokes recorded once as fixtures, replayed with no display. A
recogniser entangled with the draw loop can only be checked by hand, and then it is
tuned blind.

### 7.2 Features

Resample the stroke to 64 equidistant points, then:

| Feature | Definition |
|---|---|
| `diag` | bounding-box diagonal |
| `closed` | `dist(p_first, p_last) / path_len` |
| `fill` | `abs(shoelace_area) / (w * h)` |
| `corners` | Douglas–Peucker at `eps = 0.04 * diag`, kept where the turn exceeds 50° |
| `turn` | sum of absolute turn angles |
| `aspect` | `w / h` |

### 7.3 Decision table

Ordered; first match wins. `closed < 0.15` means the stroke returned to its start.

| # | Condition | Result |
|---|---|---|
| 1 | `closed < 0.15`, `fill > 0.80` | `rect` |
| 2 | `closed < 0.15`, `0.36 < fill < 0.68` | `diamond` |
| 3 | `closed < 0.15`, `0.68 ≤ fill ≤ 0.80`, `corners >= 5` | `hexagon` |
| 4 | `closed < 0.15`, `0.68 ≤ fill ≤ 0.80`, `0.85 < aspect < 1.18` | `circle` |
| 5 | `closed < 0.15`, `0.68 ≤ fill ≤ 0.80` | `round` |

**Area decides, not the corner count.** A corner drawn by hand spreads over several
samples and each one turns only a little, so a corner count built from adjacent samples
finds none at all — a diamond then has no corners, fails every rule and falls through to
`rect`. The filled fraction of the bounding box does not care how the corner was sampled:
a diamond fills half, a circle π/4, a rectangle nearly all. Only hexagon and circle (0.75
against 0.785) are too close to separate by area, and there the corners decide — measured
over a window of ±3 samples, not between neighbours.
| 6 | `closed >= 0.15`, `turn < 1.2 rad`, `path_len > 0.5 * diag` | `arrow` (§7.5) |
| 7 | otherwise | no match; the stroke is discarded with a visible hint |

The numbers are a starting point, owned by the fixture suite (§9): a threshold changes
only together with the fixture that forced the change.

### 7.4 Propose, then confirm

**Normative.** The recogniser returns a **candidate list**, and the shape snaps to
candidate 0 immediately. `Tab` cycles to the next candidate while the node is still
fresh (before the first commit of its label).

This single rule is what makes the whole geometric approach viable: it turns ~85%
first-guess accuracy into 100% reachable output at the cost of one keystroke, and it
removes any need for the recogniser to be clever about ambiguous strokes. A tool that
guessed silently and offered no correction would be wrong 1 shape in 7, with no way out
but redrawing.

### 7.5 Arrows and attachment

An `arrow` stroke attaches by endpoint:

- Each endpoint hit-tests against node boxes grown by a tolerance of `12` design units.
- A stroke may **begin on a node's rim** (within 14 units of its border): that drag draws
  a connector, while a drag from the middle moves the node. Without the rim rule a
  connector can never start on its own source, because that gesture is already the move —
  the line has to be begun beside the shape and aimed back at it, which is not how anybody
  draws one.
- Zero hits at an end → the stroke is discarded (a dangling edge has no Mermaid form).
- More than one hit → the **nearest centre** wins, and the resolved edge is drawn
  highlighted for one beat so a wrong pick is visible.
- `from_id == to_id` is allowed (self-edge).

Arrowheads are **not** recognised. Direction comes from the drawing direction
(first point → last point), which is unambiguous and free. The head is drawn by the
renderer, not detected.

### 7.5a The ink stands until it is read

A stroke is **not** interpreted when the pen lifts. It stays on the slide as ink, and
further strokes join it. The ink is read when either happens:

- the **right mouse button** is pressed, or
- the **settling time** passes with nothing drawn (`--settle`, 1.6 s by default).

Then the whole group is interpreted at once and replaced by what it meant.

**Why not per stroke.** A dotted line, a subroutine box and a cylinder are each drawn
with the pen lifted in between — they are several strokes by nature. Reading each stroke
on its own cannot see them at all: the short pieces fall through as "too short" and the
author watches their drawing disappear. Everything that is not a single closed outline
needs the group, so the group is the unit.

**Why a pause and not only a key.** Waiting for a key makes every shape cost a keystroke;
waiting only for a pause makes a deliberate pause unavoidable. Both are offered, and the
pause is generous enough to draw two strokes without racing.

**Picking something up ends the drawing** (normative). Selecting a node or an edge
discards whatever ink is still standing. The ink survives a pause because the author may
still be drawing; it does not survive a different intent. Strokes that meant nothing and
were already read keep nothing on the page, but a group that produced nothing stays
visible until it is read — and if the author has moved on to arranging, that leftover is
no longer a drawing in progress, it is litter over the slide they are now working on.

#### Reading a group (normative, first match wins)

| | The group | Becomes |
|---|---|---|
| 1 | one closed stroke, nothing else | that shape (§7.3) |
| 2 | one closed stroke, the others inside it | that shape, modified: two near-vertical strokes near its left and right edges → `subroutine`; one near-horizontal stroke in its top quarter → `cylinder` |
| 3 | no closed stroke, all strokes along one line | one connector between the nodes at the ends of the overall line (§7.5). Which kind it is depends on the **lengths**, not the count — see below |
| 4 | anything else | each stroke read on its own, by the rules above |

#### Dashes, or a line with heads?

Both are several strokes, so counting them cannot tell them apart — a double arrow is
three strokes exactly like a dotted line is. The **lengths** can: dashes are all a
similar fraction of the whole, while a line with heads has one stroke carrying most of it.

- longest stroke **> 40 %** of the total length → that stroke is the line; every short
  stroke whose middle sits near one of the group's ends is a head there. Both ends →
  `bidirectional`, one → `arrow`, none → `open`.
- otherwise → `dotted`.

The 40 % is measured, not chosen: three equal dashes put the longest at 33 % of the
total, while a line with two heads a third of its length sits at 60 %. An earlier 50 %
threshold failed on a real double arrow at 184 against a half-sum of 183.5 — a tie on
half a unit, decided the wrong way.

The group's **ends** are the two extreme points along its own direction, not the first
and last sample. Stroke order then does not matter, which is what lets the first head be
drawn before the line.

Rule 3 is the whole reason the ink waits: a dotted line is **drawn** dotted, and nothing
else about it says so.

**Normative — reading never destroys work.** The ink is cleared only when the reading
produced something. A group that yielded nothing stays on the slide, so drawing a head
and then taking a moment over the line does not cost the head; the **right button** is
the explicit discard. Unchanged ink is not read twice — the same verdict every settling
period is noise, not information.

### 7.6 Straightening

**Normative.** A recognised shape never keeps the stroke's wobble or its tilt. This is
not cosmetic: a Mermaid node is always axis-aligned, so a tilt has no projection at all
(§5.7) — straightening is the only faithful thing to do with it.

For a **closed** shape:

1. **Principal axis.** From the covariance of the 64 resampled points,
   `theta = 0.5 * atan2(2 * Sxy, Sxx - Syy)`. This is the straight centre line of the
   stroke — for a rectangle it runs along the long side.
2. **Stability gate.** With eigenvalues `l0 >= l1`: if `l0 / l1 < 1.25` the shape is
   near-square and `theta` is numerically meaningless (a square has no principal axis),
   so `theta = 0`. Without this gate a hand-drawn square jitters through every angle
   between two redraws.
3. **Fold** `theta` into `[-45, 45]` degrees — a rect tilted 91 degrees is a rect tilted
   1 degree with `w` and `h` swapped.
4. **De-rotate** the points by `-theta` about their centroid and take the axis-aligned
   bbox *in that frame*: this gives the true extents `w`, `h` and the centre `c`.
5. Emit the node axis-aligned at `c` with size `w` x `h`. `theta` is **discarded**.

Step 4 is why the raw bounding box is not used. A `w` x `h` rect drawn at angle `theta`
has an axis-aligned bbox of `(w*cos + h*sin)` x `(w*sin + h*cos)` — the corners stick
out. For a square at 10 degrees that is about **1.16x** in each axis, and the inflation
grows with the tilt. Snapping to the raw bbox would therefore make every slightly
crooked box bigger than the one the user drew, and make it bigger the more crooked it
was. De-rotating first returns the size actually drawn.

For an **open** stroke (arrow, line): least-squares fit through the points, endpoints
projected onto that fit. If the fit direction is within 12 degrees of an axis, it snaps
to exactly horizontal or vertical.

#### 7.6.1 Tidy-up snaps

Applied after straightening, in this order:

| # | Snap | Rule |
|---|---|---|
| 1 | grid | centre and size to 10 design units |
| 2 | size harmonisation | `w` (or `h`) within 12% of an existing node's `w` (or `h`) adopts it exactly |
| 3 | alignment | centre within 8 units of another node's centre x (or y) adopts it exactly |
| 4 | minimum | at least 60 x 36, then grown to fit the label (§6) |

Snap 2 is the one that makes a hand-drawn sheet look machine-drawn: boxes a human means
to be the same size never are.

**Normative.** Each snap is individually switchable from `Einstellungen` (§8.0) and is a
pure function on the sheet, so each is testable (§9). They are switchable because a
diagram where everything snaps is occasionally the wrong diagram — a deliberately
odd-sized node is a legitimate thing to want.

---

### 7.7 Drawing on a sequence (normative)

The recogniser is the same everywhere, but what a recognised box *becomes* depends on
the diagram.  In a `sequence`:

| Drawn | Becomes |
|---|---|
| a box whose centre is in the **head row** (the top 56 units of the page's layout) | a participant, as in every other diagram |
| a box **below** it, on or near a lifeline | a **note** (`Note right of n1`) |
| a box spanning **two** lifelines | a note over both (`Note over n1,n2`) |
| a **line or arrow** between two lifelines | a **message** (`n1->>n2`), with the head the recogniser saw: no head is `->`, a dotted stroke is `-->>` |
| a line whose head sits at its **start** | the same message, the other way round |

Below the head row a sequence has **no free positions** (§5.8.3) -- a participant put
there would be dragged into a column anyway, and the author who drew a box across a
lifeline meant "this holds from here on", which is what a note is.

The note lands on the **row it was drawn on**, not at the end: the step list is the time
axis, so appending would move a note the author placed deliberately.  Which lifeline it
belongs to is the **nearest** one, not a strict hit -- ink is drawn by a hand, and the 60
units between two columns belong to the nearer of them (unlike the connect gesture, §5.8.3,
which is a pointer and may be strict).

Both land on the **row they were drawn on** and their label opens immediately, exactly as
a new node's does (§6).

A drawn line whose two ends fall on the **same** lifeline is refused with a message
rather than turned into a self-message: at the size a hand draws, a short stroke beside
one lifeline is far more often a slip than a deliberate loop.

## 8. Chrome

### 8.0 The window's chrome (normative)

Two strips at the top, a status strip at the bottom, the canvas between:

```
+---------------------------------------------------+
| Datei  Bearbeiten  Ansicht  Einstellungen  [Kante] |  menu strip, 28 px
+---------------------------------------------------+
| [Flussdiagramm v] | Kasten Rund Kapsel Kreis ...   |  tool strip, 46 px
+---------------------------------------------------+
|                                                   |
|                      canvas                       |
|                                                   |
+---------------------------------------------------+
| bereit                             Folie 2/7  *   |  status strip, 24 px
+---------------------------------------------------+
```

- The **menu strip** carries what a menu carries everywhere: `Datei` makes, opens,
  saves and exports; `Bearbeiten` undoes, redoes, carries the clipboard and acts on
  the selection; `Format` styles the label (§5.6a); `Ansicht` switches slides and starts the
  presentation; `Einstellungen` holds what is a preference rather than an action. A
  title opens a dropdown, and the dropdown **claims the pointer** while it is open --
  the same rule as §8.2, for the same reason.
- **`Kante` appears only while an edge is selected**, and holds line, head and tail
  (§5.3) -- the only place where a composed connector is built by hand. A menu that is
  always there but whose every entry is dead says less than a menu that appears when it
  has something to say.
- **`Ansicht` lists the slides** under its fixed entries, `>` on the current one, click
  to jump. The list belongs in the menu because switching slides is a view act; it is
  built fresh each frame from the deck, so a renamed slide is renamed in the menu.
- The **tool strip** is the shapes, and its first control sets the **diagram type**. The
  type sits there because it is the one choice that changes what every other control in
  the strip means, and because a drawing surface should say what kind of drawing this is
  without opening a menu.
- **The palette is the type's vocabulary** (§5.8), and changes with it:

  | type | palette |
  |---|---|
  | `flowchart` | the seventeen shapes |
  | `state` | Zustand, Start/Ende, Wahl, Notiz |
  | `class_diagram` | Klasse, Schnittstelle, Notiz |
  | `sequence` | Teilnehmer, Akteur, Nachricht, Notiz, Block |

  A button names what it makes in *that* diagram, not the geometric shape it happens to
  use. "Zustand" is a rounded box, but calling it "Rund" in a state chart would be like
  labelling a form field by its font.
- The **status strip** carries, left, the last thing that happened (what every `status`
  message in the editor goes to), and right, the slide number plus `*` while there are
  unsaved changes (§16.2). It is drawn, not built from widgets, and claims no input: a
  click on it lands nowhere, which is what a report of state should do.

- Titles and shape buttons are **measured** (`ui.measure_text`), not placed on a fixed
  pitch: `Einstellungen` is twice as wide as `Datei`, and a fixed pitch either wastes
  the strip or lets the next label run into the one before it. Both happened.

**Normative -- chrome owns its area.** A press that *begins* on a strip never starts a
stroke: the canvas tests the pointer against its own rect only. Without this rule a drag
that starts on a button also starts drawing, and the stroke crawls out from under the
chrome.

**Normative -- an open dropdown claims the pointer**, and the canvas is asked *first*,
so the canvas must stand down while one is open (§8.2 has the same rule for the
right-click menu). A dropdown hangs over the canvas: without this, a click on
`Kante > Fuss Pfeil` also landed on empty canvas, cleared the selection, and the action
then arrived with nothing to act on -- a menu entry that did nothing, every time.

### 8.1 The left bar, and why it is gone

Until the strips were complete the window had a scrollable column of `ui.button`s on the
left, built like glbview's panel (`test/glbview/src/viewer.aiml`, its spec §4.3): file,
export, shapes, selection, slides, view. It is **removed**; every entry it had has a home:

| was in the bar | is now |
|---|---|
| Datei, Export | `Datei` (§8.0) |
| Formen | tool strip |
| Auswahl (label, image, delete) | `Bearbeiten` |
| Folien (back, forward, new, title, the list) | `Ansicht` |
| Linie / Kopf / Fuss of an edge | `Kante`, which appears with the selection |
| Praesentieren | `Ansicht` |
| the status label and the `*` | status strip |

The canvas now has the full window width, which is the point: a sheet is 1280 x 720 and
was being drawn into 82 % of the window.

**A number that meant two things.** In the bar the tail caps were actions 59..63, and
the dispatch had already spent 60 and 61 on *open* and *save as* -- it tests them first,
so `Fuss: Pfeil.` opened a file dialog and `Fuss: Kreis.` opened *save as*. Two
authors, one list of integers, no compiler to notice. The caps are **80..84** now, and
the rule is: a dispatch number is allocated once, in the table of §8.3, and a menu entry
carries its number next to its label so the two cannot drift apart.

### 8.2 Right-click menu

**The right button has two jobs, and §7.5a has the first claim.** While unread ink is
standing on the canvas, the right button *reads* it — that is what the button was given
to the author for, and taking it away mid-stroke would be the worse surprise. With no
ink waiting, the same click opens the menu below. This is written down because the two
sections contradicted each other for a while, and a reader of either one alone would
have implemented the opposite.

The menu is **target-sensitive** — one menu per thing under the cursor:

| Target | Entries |
|---|---|
| empty canvas | diagram type (`DiagramType`), direction (`Direction`), propose direction from layout (§5.4), theme, grid snap, export `.mmd`, save, open |
| node | shape kind (`NodeKind`), fill, stroke, assign/remove group, edit label, delete |
| edge | line kind (`EdgeKind`), set/clear label, flip direction, delete |
| multi-selection | group into subgraph, same fill, align, delete |

Enum-valued entries bind the enum, not a hand-written string list, so a new member
appears in the menu without a second edit (`ui.spinbox` over `enums.*`).

**Colour is a palette, not a colour picker** (normative): ten fixed swatches plus
"inherit the theme" (`0`). A sheet whose colours come from a small set stays legible
when it is exported — §5.6 turns a pair used twice into one `classDef`, and a free
picker would give every box its own near-identical shade and one `style` line each.
The author who truly wants `#8a4f2b` writes it in the file; the surface offers the set
that keeps diagrams readable.

**Normative — the menu claims input.** While open, the menu takes pointer input over
its own rect: nothing underneath is hovered or clickable, and the wheel scrolls the
menu rather than the canvas. This is stated because the opposite has already happened
in this codebase: an overlay that drew on top but claimed nothing let clicks fall
straight through to the canvas, which here would mean drawing a stroke *through* the
menu. `ui.spinbox` already shields this way (spec/44_3 §4.2) and is the model.

### 8.3 Dispatch numbers

One action integer runs the whole editor, so the ranges are written down:

| range | meaning |
|---|---|
| 1..3 | save, Markdown, Mermaid |
| 19, 26, 27 | arm the arrow gesture, label the selection, free drawing |
| 20..24, 30 | delete, slide back/forward/new, heading, present |
| 40 + n | jump to slide n |
| 50..53 | the selected edge's line (solid, dotted, thick, invisible) |
| 54..58 | its head (none, arrow, circle, cross, hollow) |
| 60, 61, 65..68 | open, save as, SVG, HTML, PowerPoint, choose image |
| 70 + n | diagram type n |
| 80..84 | its tail (none, arrow, circle, cross, hollow) |
| 100, 101 | pointer mode: drag an arrow / draw freely |
| 110 + n | arm shape n of the tool strip |
| 130..137 | zoom (fit, 50, 100, 200, in, out), grid, snap (§8.4) |

---

---

### 8.4 Ansicht — zoom, grid, snap (normative)

| Entry | Action | Key |
|---|---|---|
| `Einpassen` | the page fits the canvas; the pan is reset | `Strg+0` |
| `50 %` · `100 %` · `200 %` | that scale exactly | `Strg+5` · `Strg+1` · `Strg+2` |
| `Hineinzoomen` · `Herauszoomen` | the next step of 50, 75, 100, 150, 200, 300 % | menu only |

The steps have **no key** because aiml's key canon has no name for the `+` and `-` keys:
letters, digits and the named keys, nothing else (aiml spec/44_0 §1, and the runtime's
table agrees — there is no `Minus`/`Equal`).  Digits are what is left, so the scales got
them and the ladder is reachable from the menu.
| `Raster` | show the grid | |
| `Am Raster einrasten` | place and drop on the grid | |

**Zoom is a view transform and never changes a stored coordinate.**  Zooming in, placing
nothing, and zooming out leaves the sheet byte-identical.  This keeps §14's promise
(positions belong to the author) under a feature that looks like it moves things.
Snapping is the deliberate exception: it rounds the value that is *written*, so it does
show up in the sheet — a user who turns it on asked for exactly that.

**One origin.**  Page scale and page origin are computed in **one** place
(`EditorPaint.page_rect`), and drawing, pointer input and the script tick all read it from
there.  The formula stood in three places before zoom existed; with a zoom and a pan in it,
three copies drift apart and the pointer lands somewhere other than where the picture says
it would.  A test pins this: the same slide coordinate, placed at 100 % and at 200 %, must
store the same `x`/`y` (§9.2).

**Panning is on the right mouse button, by the drag.**  Right-press and move: the view
follows the hand.  Right-press and release without moving (less than 6 window pixels) is
the old right-click -- read the ink, or open the element menu (§8.2).  The button that
pans is the one a hand already rests on; the middle button does the same for mice that
have one.  In plane mode (§20) the drag is unbounded, which is what makes the plane a
plane.

**Panning only exists where it is needed, and it is measured from centred.**  Pan `0` is
the centred page at every zoom, so zooming in keeps the middle of the page in the middle of
the canvas instead of jumping into a corner.  While the page fits the canvas it is centred
and the pan is ignored.  Larger than the canvas, the middle mouse button drags it, clamped
so no gap can open between a page edge and the canvas edge on an axis that overflows —
a view that can be dragged into emptiness loses the drawing.

**The grid is drawn, never exported.**  10 slide units minor, 50 major, inside the page and
below the elements.  It belongs to the view, so no exporter (§5) and no PPTX page (§13)
knows about it.  Snap granularity is the minor spacing, 10 units.

## 9. Tests

Three headless suites plus one that needs a display.

| Suite | Fixture | Expected | Needs display |
|---|---|---|---|
| recogniser | `tests/fixture/stroke_*.yaml` — recorded point lists | candidate list, first entry asserted | no |
| straightening | the same stroke fixtures, incl. deliberately tilted ones | resulting `x`/`y`/`w`/`h` within 0.5 units | no |
| emitter | `tests/fixture/sheet_*.chart.yaml` | `tests/expected/*.mmd`, byte-exact | no |
| editor | scripted clicks/keys | screenshot + sheet state | **yes** |

The straightening suite must contain, at minimum, the same rectangle recorded at 0, 5,
10 and 20 degrees of tilt, all four asserting the **same** `w` x `h`. That is the
property §7.6 exists for, and the raw-bbox mistake it rules out passes every other test
in this file.

**Normative.**

- The recogniser, the straightening pass and the emitter are pure (§7.1, §7.6, §2), so
  their suites run with no window and belong in `run_tests.sh`.
- The editor suite does **not** go into that loop. A test that opens a window blocks
  until the window closes, and `run_all_tests.sh` has no timeout — one blocking test
  stops the whole suite. It runs separately, under `Xvfb` with XTEST-synthesised
  clicks, and a display-less run skips it loudly rather than reporting success.
- Byte-exact expected Mermaid is the point: §2 promises export is a pure function, and
  only a byte comparison actually checks that promise.

---

### 9.1 Driving the editor from a file (normative)

`chart --script FILE` replays input steps, **one per frame**, and then exits. The engine
can post input events (aiml spec/44_0 `input.post_*`), so a test clicks and types in the
same process and through the same code path a hand takes -- no X11 robot, no reading
pixels back.

- A step is one line: `at X Y` (slide units), `at_win X Y` (window pixels),
  `down`/`up [button]`, `key NAME`, `hold NAME` (a repeat), `type TEXT`,
  `wait N` (frames), `menu TITEL|Eintrag`, `tool NAME`, `shot FILE`, `save`.
  `#` is a comment.
- **`menu` and `tool` name what they want**, and the strip says where that is at this
  window size. They expand into the six steps a pick really is -- move, press,
  release, twice -- so the click still goes through the editor's own input path.
  A name that is not in the strip is an **error**, which is the point: a test that
  hard-codes `at_win 435 14` keeps passing after the entry moves, and then it is
  measuring the layout instead of the editor. Inserting one menu entry broke three
  scripts before this existed.
- **Coordinates are slide units.** A test that hard-codes window pixels breaks when the
  window size changes and then tests the window manager instead of the editor.
- **One step per frame**, because that is how a hand's input arrives: a press and the
  release after it are different frames, and collapsing them would test something the
  editor never sees.
- Steps run **before** the frame reads its events. `aiml_input_update` clears the event
  queue at the start of every frame, so a key posted after that point is wiped unread --
  the clicks still worked (they are latches), which is exactly the kind of half-working
  that wastes an afternoon.
- A press **re-posts the pointer** first. The window manager moves the real pointer when
  the window maps, and a button posted afterwards lands wherever that left it.
- An unknown step is an **error**, not a shrug: a script that silently skipped half its
  steps would pass while checking nothing.
- `type TEXT` takes the **rest of the line verbatim**, quotes included. `type " EUR"`
  types the quotation marks too. Written down because it looks like a shell argument
  and is not one.
- A script's **start deck** lives in `tests/fixture/script/`, not beside the export
  fixtures: the export tests take every `tests/fixture/*.deck.yaml`, and a start deck
  is an input for the editor, not something anybody expects a `.mmd` of.

The test then compares the **saved sheet** against an expected file -- the editor's own
output, not a screenshot, so a failure names the field that changed.

---

## 10. Engine support this needs

Two things were missing in AIML when this spec was written, and both are being added to
the engine rather than worked around here — an approximation in a drawing tool is a
diagram that is subtly wrong, which is worse than one that fails.

| Need | Status |
|---|---|
| Measure text to size a node | `engine.text_width(text [, font_size])` / `engine.text_height([font_size])` — aiml spec/44_6 §5i. `text_width` existed but took no size, so it could only measure in the scene font; the optional size argument is the addition. |
| Draw ink and edges | `ui.draw_line` / `ui.draw_polyline` — aiml spec/44_3 §4.6. Previously there was no 2D line primitive at all and the only route was raw `gl.draw_arrays_mode(vao, gl.LINES, n)`, a second pipeline with its own ordering. |

`chart` therefore requires an AIML that has both. Until that lands, stage 0 (§README) is
unaffected: it needs neither, since stencils carry their own geometry and a Mermaid export
measures nothing.

---

## 11. Decks and slides

A drawing is rarely one picture. A **deck** is an ordered list of slides, each slide
exactly a `Sheet` (§3.1) — so everything §2 through §7 says about a sheet holds for a
slide, unchanged.

```aiml
- model:
    name: Deck
    description: "An ordered list of slides; the unit a presentation and an export work on"
    fields:
      - [title, string, ""]            # deck heading; the index's `# ` (§13)
      - [slides, list<Sheet>]
      - [current, i32, 0]              # the slide being edited or shown; not saved
```

### 11.1 One file, or one slide

- `*.deck.yaml` carries `title:` and `slides:`, a sequence whose entries are each exactly
  a sheet mapping (§4).
- `*.chart.yaml` stays what it was and loads as a **one-slide deck**. Stage 0's
  `--sheet FILE` keeps working and keeps meaning the same thing.

**Normative — ids are per slide.** `n1` may exist on every slide, and `next_id` counts
per slide. This is not laziness: a Mermaid id is unique within *its* diagram (§5.1), and
one counter across a 40-slide deck would make every slide's export depend on the slides
before it — the opposite of §2's promise that an export is a pure function of what it
exports.

### 11.2 Why one file and not one file per slide

A deck is reordered far more often than a single slide is edited, and reordering files
means renaming them. One file reorders by moving a block, and a diff shows the move. The
cost is honest: two people editing different slides of one deck conflict in one file.

---

## 12. Images

An image is a **node kind**, not a second kind of object: `NodeKind.image` with `src`
naming the file and `text` carrying the caption. It therefore drags, resizes, aligns,
snaps and belongs to a group exactly like a box does, and none of §7's geometry needed a
second code path.

- **`src` is a path relative to the deck file's directory**, never the bytes. A deck is a
  text file that diffs and merges; a base64 blob in it would end both. It also means the
  pictures stay editable with the tools that made them.
- **A missing file is drawn as a placeholder** carrying the path, and export still writes
  the link, with **one** reported line per missing file. Writing a working link to a file
  that is not there would be a lie; writing nothing would silently drop the picture.
- **Mermaid cannot carry an image.** An image node emits as a labelled rectangle so the
  structure survives (§5.7 lists it as lost). The Markdown export (§13) is where a picture
  actually arrives, which is the reason that export exists at all.

---

## 13. Markdown export — one file per slide

```
chart --deck FILE.deck.yaml --markdown DIR
```

GitHub renders a ` ```mermaid ` block natively, so a slide exported this way **is** the
slide when the repository is browsed — no renderer, no build step, no image of a diagram
that drifts from its source.

Per slide, `DIR/NN-<slug>.md`, numbered from 01 in deck order:

```markdown
# Mitgliedsantrag

```mermaid
flowchart TD
    n1(["Eingang"])
    n2{"vollständig?"}
    n1 --> n2
```

![Formular, Seite 1](bilder/antrag_s1.png)
```

- `NN` is the 1-based slide number, two digits, so files sort in deck order in any file
  listing.
- `<slug>` is the title, lowercased, every run of non-alphanumerics folded to one `-`,
  trimmed; an empty title gives `slide`.
- `DIR/README.md` is the index: the deck title, then a numbered list linking each slide
  file. GitHub shows `README.md` when the directory is opened, so the deck has a front
  page without anybody asking for one.
- Image paths are rewritten **relative to the Markdown file**, so they resolve when GitHub
  serves the page.

**An empty title gets no heading.** The file then starts with the diagram. Inventing
„Slide 3" would put a word on the page that the author never wrote; the index (below) does
name it that way, because a link needs a label.

**Normative — speaker notes are not exported.** `Sheet.notes` belongs to the presenter
(§14) and never reaches the slide file. An export that carried them would publish them to
everyone who opens the repository, which is the one thing notes must not do.

**Normative — the export is byte-exact and ordered.** Same deck in, same bytes out, as in
§2, and for the same reason: it is the only property a test can actually check.

---

## 14. Presentation mode

A key leaves the editor and shows the current slide alone: no action bar, no grid, no
handles, the slide scaled to fit the window and centred.

| Key | |
|---|---|
| `Right` · `Space` · `PageDown` | next slide |
| `Left` · `PageUp` | previous slide |
| `Home` · `End` | first · last |
| `N` | toggle speaker notes (presenter's screen only) |
| `Esc` | back to the editor, on the slide that was shown |

**Normative — presentation mode never mutates the deck.** No drag, no stencil, no label
edit, no delete; the right-click menu does not open. Clicking is navigation, not
selection. A mode that could edit while presenting *will* edit by accident, in front of
an audience, and the damage is discovered later.

**Normative — the deck is not reflowed.** The slide is scaled, never re-laid-out:
positions are the author's (§1.1), and a presentation that moved things to fit would show
something the author never saw.

---

## 15. The editor surface

The window is the two strips of §8.0 at the top, the status strip at the bottom and the
canvas filling everything between, at the full window width. The canvas is one slide of
the deck; `Ansicht` lists the slides and switches on click.

### 15.1 Placing and editing

- A **stencil** click arms a kind; the next canvas click places that node at the cursor in
  the default size and goes straight into label editing (§6).
- **Drag** a node to move it; drag the blue halo of the selected node to resize it (§15.1a). Both snap per §7.6.1 when the
  snaps are on.
- **Click** selects, `Shift+click` adds, a drag on empty canvas is a rubber band,
  `Delete` removes the selection.
- **Freehand** (§7) needs no tool: a drag that starts on empty canvas **is** the
  stroke. Drawing is what the surface is for, and a mode in front of it is a mode the
  author has to remember. A drag that starts on a node moves it; a click on a node
  selects it; a click near an edge selects the edge. A stroke too short to recognise
  does nothing, which is what a stray click should do anyway.

  The cost is that there is no rubber-band selection: that drag is taken. When
  multi-selection arrives it needs a modifier, not a mode.
- An **edge** is drawn with the edge tool: press on the source node, drag, release on the
  target. The line follows the cursor while dragging, so what will be connected is visible
  before the button is let go. Released anywhere but on a node, nothing is created — a
  dangling edge has no Mermaid form (§7.5).
- An edge is **selected** by clicking near its line, and the bar then sets its kind or
  deletes it. Without that, a wrong arrow could only be fixed in the file.

### 15.1a Handles and the pointer (normative)

**One gesture per pixel.** The rim of an *unselected* node starts a connector (§15.1);
the blue halo of a *selected* node resizes it. The halo only exists once the node is
selected, so the two gestures never compete for the same pixel and neither needs a tool
or a modifier.

**The handle band is 12 sheet units** wide, measured on the sheet and not on the screen,
so it scales with the zoom exactly as the node does. A band in window pixels would cover
half a node at a small zoom and a hairline at a large one.

**Resizing pins the opposite edge.** The left handle moves `pos_x` and changes `width`;
the right one changes `width` alone; top and bottom do the same on the other axis. A
corner carries both axes at once. A node never shrinks below `40 x 30` sheet units: at
the minimum the dragged edge stops and the opposite one stays where it was, so a node
cannot be collapsed to nothing and lost.

**Every shape but the arrow belongs to the selected node.** A resize or move shape on
an unselected node would promise a gesture that a press there does not perform: the
press selects first. The pointer may only offer what the next click actually does.

**Pointer shapes** (aiml spec/44_0 §2.5):

| Where the pointer is | Shape |
|---|---|
| On the halo's left or right edge, or on any corner | `resize_ew` |
| On the halo's top or bottom edge | `resize_ns` |
| On the selected node's **letters** — a click starts typing | `text` |
| Elsewhere inside the **selected** node — a drag moves it | `crosshair` |
| Anywhere else, an unselected node included, the action bar included | `arrow` |

**Typing starts by clicking the letters** of the selected node, not by clicking it
anywhere: the middle of a node is how it is moved, and a click there must not put a
caret in. The target is measured with the same two calls `text_block` draws with
(`ui.measure_text`, `ui.text_height`), so the target *is* the text rather than a guess
about where the text went. An empty label keeps a caret-sized spot in the middle --
otherwise a node placed and then left empty could never be typed into again.

**The caret starts at the end** of the existing text: opening a label is for adding to
it, and a click that silently replaced a label would destroy work with one gesture and
no warning.

A corner gets `resize_ew` because the engine offers six shapes and none of them is
diagonal. That is a stated compromise, not an oversight: the corner does resize both
axes, and a cursor that merely names one of them is better than no feedback that the
pointer has reached a handle.

**`Delete` removes the selection**: the selected edge if one is selected, otherwise the
selected node **and every edge that touches it**. Deleting a node but keeping its edges
leaves the sheet pointing at something that is gone, and §5 would then project an edge
whose endpoint is never declared — invalid Mermaid produced from a sheet that looked
fine on screen.

### 15.2 What the canvas owes the rest of the spec

- Nodes draw in sheet order, so **z-order is the order in the file** — the thing a diff
  shows and a user can reason about, rather than a hidden per-node z field.
- An image node draws its picture, a placeholder when `src` is missing (§12).
- The canvas never draws outside its rect: it is a cell, and `ui.draw_*` clips to it
  (aiml spec/44_3 §4.6).

---

## 16. Files: opening, saving, picking

**The system's dialog first, chart's own as the fallback** — the arrangement glbview
already uses. aiml has no dialog call of its own, but it can run one: `sys.exe` starts
`zenity`, `kdialog`, `yad` or `qarma` and reads the chosen path from its output. That
dialog is the one the author knows, with their places, their recent folders and their
keyboard habits, and nothing chart draws will ever match it.

When no such program is installed, chart draws the browser itself from `io.list_dir`.
That is not a lesser mode to be removed later: a machine without zenity must still be
able to open and save, and an export that depends on an optional package is an export
that fails on someone else's machine.

### 16.1 The browser (normative)

The rules below describe the **fallback** browser. The system dialog brings its own
behaviour and chart does not fight it; it only states the start directory, the filter
and, when saving, the suggested name.

- It is **modal over the canvas**: while it is open the canvas takes no presses and the
  ink is not read. §6's rule stands — one consumer for the keyboard, and while the
  browser is open that consumer is the browser.
- Entries are **directories first, then files, each sorted by name**; entries whose name
  begins with `.` are skipped. The current directory is shown as a header, `../` goes up
  and is absent at the root.
- It opens in the directory of the **current file**, not in the process's working
  directory: the next file an author wants is almost always next to the last one.
- A **filter** per purpose: `open` shows `*.chart.yaml` and `*.deck.yaml`, `image` shows
  `*.png *.jpg *.jpeg`, `export` shows every directory and no files at all, because its
  answer is a directory.
- A click on a directory enters it; a click on a file **selects** it; the confirm button
  (or `Enter`) answers. `Escape` closes with no answer, and no answer means **nothing
  happens** — not "export to the directory that happened to be open".

### 16.2 Open, save, save as

- The deck remembers the path it came from. `Ctrl+S` writes back to it; with no path yet
  it behaves as save-as.
- Save-as asks for a **name** as well as a directory, and refuses an empty name rather
  than inventing one.
- The sheet is **dirty** from the first edit that changes it, and the window title and
  the bar say so. Writing clears it.
- Opening another file **while dirty asks first**. The question has two buttons, and the
  third answer comes from asking twice: "save the changes?" and then the file dialog,
  whose cancel leaves everything as it was. Three-button dialogs are spelled differently
  by zenity and kdialog and report the third answer through the exit code — a wrong
  guess there would discard an hour of arranging silently, which is exactly what this
  question exists to prevent.

### 16.3 Images

An image node's `src` is picked with the same browser (`image` filter). The path is
stored **relative to the deck file** when it is below the deck's directory, absolute
otherwise: a deck that is moved or shared with its images next to it keeps working, and
one that points into someone's home directory says so plainly instead of breaking
silently somewhere else.

---

### 16.4 Undo and redo (normative)

A snapshot is the **deck's own YAML** -- the same bytes `Speichern` writes. Undo
restores through the reader that opens a file, so the two cannot drift apart; a
second, cleverer representation would be a second thing to keep in step.

- A step is recorded **when the hand comes to rest**: the frame loop notes a change
  only while no mouse button is down and no label is being edited. A drag writes the
  sheet on every frame, and an undo per mouse frame is an undo nobody can use.
- A snapshot equal to the one before it is **not** recorded, so a gesture that ends
  where it began costs nothing.
- The **view is not part of the step**: the current slide, the selection and the ink
  are not restored. An editor that jumps to another slide on undo is the thing people
  complain about in other editors. The slide index is kept and clamped, because undo
  of "new slide" must not leave the window looking at a slide that is gone.
- A new change after an undo **drops the redo chain**, as everywhere else.
- Depth is 100 steps. Keys: `Strg+Z`, `Strg+Y`; entries: `Bearbeiten`.
- `Datei > Neu` starts an empty deck with one slide and **starts a new history**: the
  old one belongs to a document that is no longer open.

---

## 17. Export formats

§2 stands: the sheet is the document and every export is a projection. What differs is
how much of the sheet survives, so each format says what it keeps and what it drops.

| Format | Flag | Keeps | Drops |
|---|---|---|---|
| Mermaid | `--mermaid FILE.mmd` | structure, shapes, colour, groups | **coordinates, sizes, anchor sides** (§5.7) |
| Markdown | `--markdown DIR` | one file per slide, title, notes-free body, the Mermaid inline | as Mermaid |
| **SVG** | `--svg DIR` | everything the canvas shows: coordinates, sizes, colour, text | group boxes — the canvas does not draw them either (§15.2) |
| **PPTX** | `--pptx FILE` | one slide per sheet, as **editable** PowerPoint shapes with text | groups, dotted-edge nuance, the exact font |
| **HTML** | `--html FILE` | one self-contained deck, arrow keys, needs no PowerPoint | whatever the SVG drops |
| **PNG** | `--png DIR` | pixels, one file per slide | everything structural |

**PDF is deliberately absent.** `soffice --headless --convert-to pdf` turns the PPTX
into one, and a PDF writer inside chart would be a second renderer to keep in step with
the canvas forever. A format that another tool already derives from our output is not
our job.

**Not planned, with reasons:** PlantUML and Graphviz DOT duplicate Mermaid's role and
would double the projection surface for nothing; JSON and CSV would be a second
serialisation of the data the sheet already is (§4).

### 17.1 SVG (normative)

- One file per slide, named as the Markdown export names its files (§13), extension
  `.svg`.
- The page is the slide: `viewBox="0 0 1280 720"`, so the sheet's units ARE the SVG
  units and no scale has to be reasoned about.
- Node order is sheet order (§15.2: z-order is file order). Edges draw after nodes so an
  arrow is never hidden under a box.
- Text is `<text>` with `text-anchor="middle"`, not paths: a diagram whose labels can be
  searched and copied is worth more than one whose font is guaranteed.
- Deterministic: same sheet, same bytes. No timestamps, no random ids — §9's byte-exact
  tests depend on it. Numbers carry at most one decimal and never an exponent, so one
  value has one spelling.
- An **edge label is drawn twice**: a white outline first, the letters on top. The single
  attribute that does this (`paint-order`) is not understood everywhere, and a renderer
  that ignores it paints the outline OVER the glyphs -- the label then disappears instead
  of standing out. Two elements work in every renderer.
- Groups are not drawn, because the canvas does not draw them (§15.2). Mermaid is the
  export that carries them (§5.5).

### 17.2 PPTX (normative)

- OOXML. Slide size 12192000 x 6858000 EMU (16:9) at 9525 EMU per sheet unit, so the
  1280x720 page maps exactly and nothing is scaled.
- The archive is written by chart, not by `compress.zip`: that call puts a directory's
  contents **under that directory's own name** inside the archive, and OOXML parts must
  sit at the root. Entries are STORED rather than deflated and carry a fixed
  1980-01-01 timestamp — that costs a little size and buys a package that is a pure
  function of its contents, which is the same promise §17.1 makes and the only reason
  the test below can compare bytes at all.
- Images are **embedded** in `ppt/media/`, never linked: a link breaks the moment the
  deck is mailed, which is the normal fate of a deck. Paths are resolved against the
  deck's directory (§16.3), so exporting from elsewhere does not turn every picture
  into a missing file.
- Shapes are **real** `p:sp` with `a:prstGeom` — `rect`, `roundRect` (a stadium is the
  same with `adj 50000`), `ellipse`, `diamond`, `hexagon`, `can` for a cylinder and
  `flowChartPredefinedProcess` for a subroutine — and the label in `a:t`. The point of a
  PPTX is that someone can edit it afterwards; a slide holding one flat picture would be
  a screenshot with extra steps.
- Edges are `p:cxnSp` straight connectors with the arrow head in `a:tailEnd`.
- Two tests, because either alone would lie: the parts are unpacked and compared
  **byte-exact**, which catches every silent change to the projection; and
  `soffice --headless --convert-to pdf` must read the finished file, because only a real
  reader can say whether the container is valid at all. A byte comparison would happily
  bless a package no tool can open, and a converter that succeeds says nothing about
  which shapes are inside.

### 17.3 HTML (normative)

One file, no network: each slide is the §17.1 SVG inlined, `ArrowRight`/`ArrowLeft`
switch, `?slide=N` opens one directly. No external script or font, because an export
that needs a CDN stops working exactly when it is needed — offline, in a train, in five
years.

## 18. Reading Mermaid back in

Mermaid can be **imported**, and §2 is the reason this section is long: the sheet is the
document, Mermaid is a projection that threw coordinates away (§5.7). Reading it back is
therefore not the inverse of writing it — it is a **reconstruction**, and chart says so
instead of pretending.

### 18.1 What an import is, and is not (normative)

- An import **invents the layout**. The nodes get positions chart computed, not positions
  anyone chose. Importing a diagram that was exported from a sheet does **not** restore
  that sheet: `sheet -> mmd -> sheet` keeps the structure and loses the arrangement,
  every time.
- The other direction **is** exact and is tested as such: `mmd -> sheet -> mmd` gives the
  same bytes back for every file chart wrote, colour included. That is the honest shape
  of the promise -- what Mermaid can carry survives a round trip, what it cannot was
  never in the file to begin with.
- Therefore an import **never writes over the source sheet**. It produces a new sheet,
  and chart refuses to import onto a path that already exists unless asked twice.
- An import is **deterministic**: the same Mermaid gives the same sheet, byte for byte.
  Otherwise the tests of §9 cannot exist and two authors importing the same file would
  get different diffs.
- **Unknown syntax is reported, never dropped in silence.** Every line chart does not
  understand is named with its number and its text, and the import continues. A diagram
  that quietly lost three edges is worse than one that failed, because nobody looks for
  what is not there.

### 18.2 The subset chart reads (normative)

| Mermaid | becomes |
|---|---|
| `flowchart TD\|LR\|BT\|RL`, `graph …` | `dtype: flowchart`, `dir:` |
| `id["text"]`, bare `id` | `kind: rect` |
| `id("text")`, `id(["text"])` | `round`, `stadium` |
| `id(("text"))`, `id{"text"}`, `id{{"text"}}` | `circle`, `diamond`, `hexagon` |
| `id[("text")]`, `id[["text"]]` | `cylinder`, `subroutine` |
| `a --> b`, `a --- b`, `a -.-> b`, `a ==> b`, `a <--> b`, `a ~~~ b` | `arrow`, `open`, `dotted`, `thick`, `bidirectional`, `invisible` |
| `a -->\|"label"\| b`, `a -- label --> b` | the edge's `text` |
| `subgraph id ["title"] … end` | a `Group`, and every node inside carries its id |
| `<br/>` inside a label | a newline |
| `classDef NAME fill:#rrggbb,stroke:#rrggbb` + `node:::NAME` | the node's `fill`/`stroke` (§5.6) |
| `style NODE fill:#rrggbb,stroke:#rrggbb` | the same, for a colour used once |
| `linkStyle N stroke:#rrggbb` | that edge's `stroke` (§5.6) |
| `direction LR` inside a `subgraph` | reported as unread: a sheet has ONE direction (§5.4) |
| YAML front matter (`---` … `---` at the top) | skipped, and `title:` in it becomes the sheet's title |
| `click` | reported as unread, never silently skipped |

A node named only in an edge (`a --> b` with no declaration for `b`) is created as a
`rect` with its id as the label: Mermaid allows it, so refusing it would reject valid
files over a formality.

### 18.3 The layout chart invents (normative)

- Nodes are put in **layers from the roots outward**: a node nothing points at is a root
  on layer 0, and a node is placed **once** -- the first edge out of a placed node fixes
  its layer, and a back edge into it changes nothing. Relaxing instead (always one below
  the deepest node that points at it) lets a cycle push its own members down a layer per
  pass: a three-node loop walked off the page before this was written down. A diagram
  that is one big cycle has no root at all, and then the first node **declared** is the
  root -- some node has to be, and the file's order is the only ordering Mermaid carries.
- Layers run **down for `TD`/`BT` and across for `LR`/`RL`**, so the drawing reads the way
  the author's `flowchart TD` said it should.
- Inside a layer, nodes keep **declaration order** — the order of the file is the only
  ordering information Mermaid carries, and inventing a better one would make the result
  depend on chart's mood rather than on the input.
- `linkStyle` numbers edges in **declaration order**, which is the order chart read
  them, so `linkStyle 2` is the third edge on the sheet. A number past the end is
  reported rather than wrapped around.
- A `classDef` may be declared after the nodes that use it, so colour is applied once the
  whole file is read. Guessing from the order would lose colour on a file Mermaid itself
  accepts.
- Spacing is fixed: a node is `210 x 76`, with `40` between neighbours and `70` between
  layers, and each layer is centred on the page. Fixed numbers, because §18.1 promises
  the same bytes for the same input.
- The result is a **starting point to drag around**, not a finished drawing. chart says
  so in the status line after an import, because an author who believes the layout is
  meaningful will read structure into an accident.

### 18.4 Markdown (normative)

A `.md` file is read as a **slide**, which is the inverse of §13 writing one: that is
the shape this import is built to close, so `chart -> md -> chart` keeps the title, the
prose and the diagram.

- A level-1 heading (`# …`) is the slide's **title**. A second one starts a **new
  slide**, as does a `---` rule on its own line. Nothing else splits slides.
- A fenced ```` ```mermaid ```` block is read by §18.2 and laid out by §18.3, below the
  prose.
- Every other line is **prose** and becomes `text` nodes, in file order, one node per
  paragraph (blank line ends a paragraph). The slide's own order is preserved: prose
  that stood before the diagram stays above it.
- **Not interpreted yet**: tables, lists, images, links, emphasis. They are kept as the
  **plain text they are written as**, so nothing is lost from the file — a table arrives
  as its pipe-and-dash lines. Dropping them would be worse, and rendering them is a
  separate piece of work that has to be done properly or not at all.
- Other fenced blocks (` ```python `) are kept as prose too, fence lines included, so
  that a code sample in a document survives being opened here.

**Why prose is a node and not a slide field.** A slide can hold several paragraphs in
several places, and once it is on the sheet the author will want to move it, widen it
and colour it like everything else. A single `notes`-style string could do none of that,
and §14 already reserves `notes` for what the presenter sees and the audience does not.

---

---

## 20. The plane (normative)

A document is read in one of two **modes**, and the file says which:

| Mode | |
|---|---|
| `slides` | one sheet at a time, centred, as every chapter before this one describes |
| `plane` | every sheet at once, as a **frame** on one endless surface |

### 20.1 A frame is a sheet

The plane adds no new kind of thing.  A frame **is** a `Sheet`, drawn at its own origin
`plane_x` / `plane_y`, and its page keeps the fixed 1280x720 of §14 -- so a diagram looks
the same in both modes, and every projection in §5, §13 and §17 is unchanged: one Mermaid
and one SVG **per frame**, PPTX frames in list order, presentation walking them in list
order.

**Everything belongs to exactly one frame.**  There are no loose elements between frames:
a plane whose notes live nowhere would export a document that is missing them, and §5's
promise is that the export is the drawing.  Drawing on empty plane therefore **creates a
new frame** there, snapped to the frame grid, and the element lands inside it -- a new
diagram is made by drawing one, not by a menu.

**Moving a frame does not reorder the deck.**  The list order is the document (it decides
export, presentation and PPTX); the plane position is where it sits.  Two authors who
disagree about reading order would otherwise fight over the layout.

### 20.2 The tab

Each frame carries a **tab** above its top-left corner, 28 units high, showing the sheet's
title (or `(ohne Titel)`), and the tab is the **handle**: dragging it moves the frame and
clicking it makes that frame the current one.  A frame without a handle could only be
moved by one of the gestures that already mean something inside it.  Renaming is
`Bearbeiten > Ueberschrift`, the same entry that names a slide (§8.0) -- a frame is a
sheet, so it is the same question.

### 20.3 Which frame is current

Pressing anywhere inside a frame makes it current, and everything the editor does -- the
armed stencil, the label, the clipboard, undo -- works on that frame's sheet, exactly as
it works on the current slide today.  The status strip names it (`Rahmen 3 von 7`).

A press on empty plane keeps the current frame, so the strips never act on nothing.

### 20.4 The view

Pan is **unbounded** here: §8.4's clamp is a slide-mode rule, because a slide is a page
and a plane is not.  `Einpassen` fits **all** frames, not one page.  Zoom is the same
ladder; the grid, when it is on, is the plane's, not the page's.

**The view is held by a focus, in plane units** -- the plane point shown at the centre of
the canvas -- and not by a pixel offset.  `Einpassen` keeps recomputing the focus, so it
follows the content; any other zoom leaves the focus where the hand put it.  This is what
makes dragging a frame work at all: with the view anchored to the content, moving a frame
moves the content's centre, the view corrects itself, and the plane crawls out from under
the hand.  Taking a frame by its tab, or panning while fitted, therefore **fixes the
zoom** at its current value and says so in the strip.

### 20.5 What the file says

```yaml
mode: plane            # omitted means `slides`
slides:
  - title: "Login"
    plane_x: 0
    plane_y: 0
    ...
```

A file written before this chapter has no `plane_x`/`plane_y`.  Opening it in plane mode
lays the frames out in **one row**, in list order, 160 units apart, and writes those
positions on the next save: a layout that is computed fresh every time would move a
document that its author had already arranged.

---

## 19. Stage plan for the surface

| Stage | Content |
|---|---|
| **0** (done) | Sheet model, YAML load, Mermaid projection, headless export, venv install |
| **1** | Deck model, slides, Markdown export per slide, images in the model — all headless and byte-exact testable |
| **2** | The window: action bar, canvas, stencils, selection, drag, label editing |
| **3** | Presentation mode, image drawing, slide strip |
| **4** | Freehand recognition (§7) and straightening (§7.6) |
| **5** | Files (§16) and the export formats of §17 |
| **6** | Reading Mermaid back in (§18) and Markdown with it (§18.4) |

Stages 1 and 3 are deliberately split: everything in stage 1 can be tested without a
display, and that is where the export promises of §2 and §13 are actually checked. The
window is then only the way a human reaches it.
