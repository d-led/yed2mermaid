# yed2mermaid

Convert [yEd](https://www.yworks.com/products/yed) GraphML flowcharts into
[Mermaid](https://mermaid.js.org/) flowcharts.

One statically linked Zig binary, no runtime dependencies, no network access. It
reads a `.graphml` file you already own and prints (or writes) Mermaid text.

```console
$ yed2mermaid example/example.graphml -o example/example.mmd
```

Install with Homebrew, Chocolatey, or download an archive from the
[releases](https://github.com/d-led/yed2mermaid/releases):

```console
$ brew install d-led/d-led/yed2mermaid      # macOS and Linux
> choco install yed2mermaid                 # Windows
```

Release archives come with a `SHA256SUMS` file; the published `.rb` formula is
generated from it.

The result of that command is [example/example.mmd](example/example.mmd); the
input is [example/example.graphml](example/example.graphml). To look at it
without a Mermaid toolchain, open
[example/index.html](example/index.html) in a browser: the page carries the
diagram inline and loads Mermaid from a CDN. [example/images.html](example/images.html)
is the same drawing with `--images`, so the embedded pictures appear.

## What is preserved

* **Groups** become `subgraph` blocks at any nesting depth. All groups are
  emitted expanded, even when the document stores them folded.
* **Edges to a group** (a yEd arrow that ends on the group itself) become edges
  to the subgraph id; edges that end on a member node stay attached to that
  node.
* **Shapes** are mapped from the yEd palette configuration or from `y:Shape`.
* **Fills, borders, border styles and text colours** are read from the document
  and emitted as `style` statements.
* **Edge labels, line styles (solid/dashed/dotted) and line widths** are kept;
  the dash pattern and width are restored through `linkStyle`.
* **UML class members** become extra label lines separated by a rule.
* **Pictures** become image nodes once `--images` is given; the bytes yEd
  embedded in the document are written next to the diagram. See
  [Pictures](#pictures).
* **Flow direction** is inferred from the drawing when `--direction auto`
  (default), or set explicitly. The same geometry heuristic is applied inside a
  group: a group whose own edges run sideways gets `direction LR` (or `RL`),
  but only when none of its members connect to the outside — Mermaid ignores a
  subgraph direction in that case.

## What is marked instead of guessed

Every node is classified as one of three treatments:

| Treatment | Realizers | Output |
|---|---|---|
| exact | `ShapeNode` (`y:Shape`), `GenericNode` flowchart/ER/SBGN/BPMN families | mapped shape, no comment |
| approximate | shapes without an exact Mermaid equivalent (document, loop limit, window pane, UML class, …) | nearest shape plus a `%% yed2mermaid:` comment and a warning on stderr |
| unknown | `TableNode`, unrecognised realizers | purple dashed box, comment and warning |

A picture node is a shape of its own: without `--images` it is marked as
unknown and says the picture was left out; with `--images` it becomes an image
node and keeps the size it had in the drawing.

## Build

Zig 0.17 or newer.

```console
$ zig build                 # debug binary in zig-out/bin
$ zig build test            # unit tests, also regenerates the example outputs
$ zig build run -- example/example.graphml
$ zig build dist            # release binaries for five targets
```

`zig build dist` writes stripped `ReleaseSmall` binaries to `zig-out/dist/`:

| Target | Linking |
|---|---|
| `aarch64-macos` | system libraries only |
| `x86_64-macos` | system libraries only |
| `x86_64-linux-musl` | fully static |
| `aarch64-linux-musl` | fully static |
| `x86_64-windows` | system libraries only |

The same actions are scripted for convenience, with a PowerShell twin for each:
`scripts/{fmt,test,build,demo,dist}.sh` and `.ps1`.

## Usage

```text
yed2mermaid [options] <file.graphml|->

  -o, --output <path>       write to <path> instead of stdout
  -d, --direction <dir>     auto (default), td, lr, bt, rl
      --style <mode>        yed (default) or none
      --plain               shorthand for --style none
      --layout <name>       elk (default), dagre, renderer-default
      --config <json|file>  Mermaid config merged over the defaults
      --title <text>        title in the front-matter
      --no-front-matter     omit the front-matter block
      --links               emit click lines for yEd node URLs
      --images[=<dir>]      write the pictures the drawing embeds into <dir> and point
                            the diagram at them; without <dir> they go to
                            <output>-images ("auto" says the same)
      --edge-filler         give label-less edges invisible labels so they keep a visible shaft (default)
      --no-edge-filler      emit label-less edges exactly as drawn, which can shrink them to arrow heads
      --quiet               do not print warnings
  -h, --help                show this help
  -V, --version             show the version
```

Reads from stdin when the input is `-`. Exit codes: `0` success, `1` usage
error, `2` input or output error.

### Configuration

The output starts with a Mermaid front-matter block (the documented
configuration mechanism since Mermaid 10.5):

```yaml
---
config:
  layout: elk
---
```

`--layout` selects `elk`, `dagre` or `renderer-default`. Anything passed with
`--config` is merged over the defaults and wins on conflicts; keys are emitted
in sorted order, so the output is byte-stable. The value may be a JSON object or
the path to a file containing one:

```console
$ yed2mermaid --config '{"theme":"forest","flowchart":{"curve":"linear"}}' chart.graphml
$ yed2mermaid --config mermaid.json chart.graphml
```

`elk` needs the viewer to have it. Mermaid CLI and the editors ship it, and
`example/index.html` registers it, but a hand-written page that loads Mermaid
from a CDN as an ES module silently falls back to dagre unless it also imports
`@mermaid-js/layout-elk` and calls `mermaid.registerLayoutLoaders(elkLayouts)`.
The diagram then comes out in a different shape, which looks as if the converter
had ignored the front-matter.

`--no-front-matter` drops the block entirely, which is useful for renderers that
predate 10.5 (they ignore it rather than fail, but the output is smaller).

### Pictures

yEd embeds a picture in the document (`<y:Resources><y:Resource>`), and the node
only refers to it by id, so there is nothing a viewer could fetch. `--images`
writes those bytes out and turns each picture node into a Mermaid image node of
the size it was drawn:

```console
$ yed2mermaid --images=pictures chart.graphml -o chart.mmd
$ open chart.mmd          # n3_n0@{ img: "pictures/n3_n0.svg", label: "person 1", pos: "b", h: 67, w: 57 }
```

The reference is relative to the diagram, so `pictures` means "next to the
diagram". Without a value, the directory is `<output>-images` (`chart-images`
above); with no `-o` it follows the input document's name. Files are named after
the node's Mermaid id, and the format is sniffed from the bytes — SVG text stays
SVG, base64 resources become `.png`, `.jpg` or `.gif`. A node that points at an
image by URL is used as it is, with nothing written out.

Pictures are the one thing whose size is copied: a Mermaid image node has no
intrinsic size. Only the height is emitted, together with `constraint: "on"`;
Mermaid then takes the width from the picture's own aspect ratio. Without the
constraint it stretches the image to the node's wrapping width (200 px by
default) whenever the node has a label, which squashes any picture.

## How the mapping is done

All tables live in `src/shapes.zig`. Two kinds of names are mapped:

* the palette configuration identifier, e.g. `com.yworks.flowchart.decision` →
  diamond, `com.yworks.flowchart.document` → parallelogram (approximate);
* `y:Shape/@type`, e.g. `roundrectangle`, `ellipse`, `diamond`, `star8`.

BPMN stores the concrete kind in a style property (`com.yworks.bpmn.type`); the
family (activity, gateway, event, artifact, conversation) picks the glyph and
the concrete kind is named in the node's comment.

Font Awesome icons are intentionally not used: Mermaid renders `fa:` only when
the host page loads Font Awesome's CSS, and a diagram carries no palette name to
key an icon on. Subtype information therefore appears as a comment.

| yEd shape | Mermaid |
|---|---|
| rectangle, roundrectangle, ellipse | `["…"]`, `("…")`, `(["…"])` |
| diamond, hexagon, parallelogram, trapezoid | `{"…"}`, `{{"…"}}`, `[/"…"/]`, `[/"…"\]` |
| subroutine, database | `[["…"]]`, `[("…")]` |
| circle | `(("…"))` |

## Fidelity limits

* The layout is re-computed by Mermaid; manual positions and bend points are not
  carried over. Only the flow direction is inferred from the drawing.
* Mermaid sizes a node from its label. The generated `style` statements only set
  paint properties — `fill`, `stroke`, `stroke-width`, `stroke-dasharray`,
  `color` — and never width, height, padding or font size, so yEd node sizes are
  not reproduced. A group whose members were large in yEd (pictures, wide boxes)
  becomes as small as its labels, and its internal edges shrink with it.
* ELK packs the layers inside a subgraph tightly, and Mermaid hard-codes that
  spacing: `flowchart.nodeSpacing` is a Dagre option, and Mermaid's link-length
  hints (`--->`) are ignored by ELK. The direction heuristic above removes most
  of the sting by laying a sideways group out sideways, but a short edge between
  two stacked layers can still look stubby. Every label-less edge therefore
  carries a zero-width space as its label, which makes Mermaid reserve the same
  room a real label would: measured on the example, the gap between the two
  picture nodes grows from 84 px to 138 px, and a bidirectional edge between two
  adjacent nodes keeps a shaft instead of collapsing into two arrow heads.
  `--no-edge-filler` restores the bare edges. `--layout dagre` is the other way
  to buy room, at the cost of a much wider diagram.
* Gradients (`y:Fill/@color2`) collapse to the first colour.
* Ports, edge routing, drop shadows, labels positioned outside the node and
  collapsed groups are not reproduced.
* Non-flowchart palette families are approximated or marked as unknown rather
  than rendered faithfully.

## Development

`example/example.graphml` and `example/palette.graphml` are hand written test
fixtures. `example/example.mmd`, `example/example.plain.mmd`,
`example/example.images.mmd` and `example/palette.mmd` are generated: the test
suite rewrites them on every run, so they can never go stale, and a change to
them shows up as a diff to review and commit. `scripts/demo.sh` produces the
same files through the installed binary, plus `example/pictures` (the extracted
pictures) and the preview pages `example/index.html` and `example/images.html`,
built from `scripts/preview.html`. Open the pages in a browser; the second one
shows what `--images` buys.

## Continuous integration

`.github/workflows/ci.yml` checks formatting, runs the test suite (its summary
is written to the run page), regenerates the example outputs through the CLI and
fails when the committed ones are out of date, then builds the release binaries
and uploads them as build artifacts.

`.github/workflows/release.yml` runs only for `v*.*.*` tags. It tests, builds
the archives (`scripts/package.sh`), publishes them with `SHA256SUMS` and the
generated Homebrew formula, then updates the tap and the Chocolatey package when
the credentials are configured:

| Secret | Used for |
|---|---|
| `PUBLISHER_TOKEN` | pushing `yed2mermaid.rb` to `d-led/homebrew-d-led` |
| `CHOCOLATEY_API_KEY` | `choco push` to community.chocolatey.org |

Both jobs skip themselves when their secret is absent, so a tag never fails
because publishing is not configured. Version tags are protected: they cannot be
deleted, moved or rewritten.

Every action is pinned by commit; `actions-up` keeps the pins current.

## Packaging

| Script | Result |
|---|---|
| `scripts/package.sh <version>` | `dist/packages` with five archives and `SHA256SUMS` |
| `scripts/generate-homebrew-formula.sh` | the formula, from the four Unix checksums |
| `scripts/generate-chocolatey-package.sh` | substituted nuspec and install script, packed when `choco` is available |

Each has a PowerShell twin.

## Legal notes

Not legal advice. The statements below summarise yWorks' own published material,
which is the basis on which this project exists.

**The tool reads a file format, not the application.** yEd's licence governs the
yEd application; it does not restrict the GraphML format. yWorks staff have
confirmed that tooling which parses or generates yEd-flavoured GraphML may be
published, and that the `y` and `yed` XML namespaces are not restricted by the
licence ([Q&A 15454](https://yed.yworks.com/support/qa/15454/allowed-publish-bindings-ygraphml-generated-manually-modified),
[Q&A 2755](https://yed.yworks.com/support/qa/2755/allowed-have-pregenerated-graphml-namespaces-extensions)).

**Your diagrams are yours.** yWorks states that "the diagrams that you create
belong to you" and that you may use them in any way you like
([Q&A 8](https://yed.yworks.com/support/qa/8/can-i-use-yed-for-free-even-for-commercial-purpose)).
This tool only transforms a document you already own.

**What this project deliberately does not do.** It never invokes, scripts,
embeds, bundles or redistributes yEd, and it contains no yWorks code. The yEd
Software License Agreement states that the software "may not be used as part of
an automated process" and forbids distribution of the software
([licence](https://www.yworks.com/resources/yed/license.html), sections 1 and 6).
yed2mermaid is an independent file converter with no connection to yWorks'
layout engines.

**No yWorks assets are included.** No palette definitions, icons, images, fonts,
colour swatches or schema-generated code. The tables in `src/shapes.zig` are
hand written and only associate yEd's public identifier strings with Mermaid's
own shape vocabulary; every colour, border and label in the output is read from
the input document. `--images` copies the pictures out of your own document
byte for byte and writes them nowhere else.

**Markers.** The licence notes that yEd may insert markers into the files it
writes. Those are comments; the parser ignores them, so such files convert
normally.

**If you need automated layout from yWorks technology** rather than a converter,
that is yFiles, the commercial toolkit — this project is not a substitute.

**Trademarks and affiliation.** yEd and yWorks are trademarks of yWorks GmbH.
This project is independent, unaffiliated with and not endorsed by yWorks.

## License

MPL-2.0. See [LICENSE](LICENSE).
