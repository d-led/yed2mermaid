# What the conversion preserves

Back to the [README](../README.md).

## Kept from the drawing

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
  embedded in the document are written next to the diagram.
* **Flow direction** is inferred from the drawing when `--direction auto`
  (default), or set explicitly. The same geometry heuristic is applied inside a
  group: a group whose own edges run sideways gets `direction LR` (or `RL`),
  but only when none of its members connect to the outside — Mermaid ignores a
  subgraph direction in that case.

## Marked instead of guessed

Every node is classified as one of three treatments:

| Treatment | Realizers | Output |
|---|---|---|
| exact | `ShapeNode` (`y:Shape`), `GenericNode` flowchart/ER/SBGN/BPMN families | mapped shape, no comment |
| approximate | shapes without an exact Mermaid equivalent (document, loop limit, window pane, UML class, …) | nearest shape plus a `%% yed2mermaid:` comment and a warning on stderr |
| unknown | `TableNode`, unrecognised realizers | purple dashed box, comment and warning |

A picture node is a shape of its own: without `--images` it is marked as
unknown and says the picture was left out; with `--images` it becomes an image
node of the height it had in the drawing.

## How names are mapped

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
  Pictures are the exception: their height is carried over (see
  [usage](usage.md#pictures)).
* Gradients (`y:Fill/@color2`) collapse to the first colour.
* Ports, edge routing, drop shadows, labels positioned outside the node and
  collapsed groups are not reproduced.
* Non-flowchart palette families are approximated or marked as unknown rather
  than rendered faithfully.
