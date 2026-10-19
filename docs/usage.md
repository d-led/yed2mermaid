# Using yed2mermaid

The options themselves are in the generated [command line](cli.md) page — this
one explains the ones with a story behind them. Back to the
[README](../README.md).

The output goes to stdout unless `--output` is given; warnings about shapes the
converter had to approximate go to stderr. Exit status is `0` on success, `1`
for a usage error and `2` when the input cannot be read or the output written.

## Configuration

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

`--no-front-matter` drops the block entirely, which is useful for renderers that
predate 10.5 (they ignore it rather than fail, but the output is smaller).

## Pictures

yEd embeds a picture in the document (`<y:Resources><y:Resource>`) and the node
only refers to it by id, so there is nothing a viewer could fetch. `--images` writes those bytes out and turns each picture node into a Mermaid image
node (Mermaid 11.3 and newer):

```console
$ yed2mermaid --images=pictures chart.graphml -o chart.mmd
$ grep person chart.mmd
    n3_n0@{ img: "pictures/n3_n0.svg", label: "person 1", pos: "b", h: 67, constraint: "on" }
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

## Mermaid versions

The generated text is plain Mermaid; how much of it a viewer understands
depends on the viewer. The table of what needs which version is on the
[README](../README.md#mermaid-versions); the two traps are these:

`--no-front-matter` is the escape hatch for old renderers: the diagram itself
then works from 9.0 on.

`elk` needs the viewer to *have* it. Mermaid CLI and the editors ship it, and
`example/index.html` registers it, but a hand-written page that loads Mermaid
from a CDN as an ES module silently falls back to dagre unless it also imports
`@mermaid-js/layout-elk` and calls `mermaid.registerLayoutLoaders(elkLayouts)`.
The diagram then comes out in a different shape, which looks as if the converter
had ignored the front-matter.

ELK also packs the layers inside a subgraph tightly, and Mermaid hard-codes that
spacing: `flowchart.nodeSpacing` is a Dagre option, and Mermaid's link-length
hints (`--->`) are ignored by ELK. The direction heuristic removes most of the
sting by laying a sideways group out sideways, and every label-less edge
carries a zero-width space as its label so Mermaid reserves room for it — a
short edge then keeps a shaft instead of collapsing into its arrow heads.
`--no-edge-filler` restores the bare edges, `--layout dagre` is the other way to
buy room, at the cost of a much wider diagram.
