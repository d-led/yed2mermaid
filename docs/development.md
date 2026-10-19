# Development

Back to the [README](../README.md).

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

Every action is scripted, with a PowerShell twin for each:
`scripts/{fmt,test,build,demo,dist}.sh` and `.ps1`.

## The example in `example/`

`example/example.graphml` and `example/palette.graphml` are hand written test
fixtures. `example/example.mmd`, `example/example.plain.mmd`,
`example/example.images.mmd` and `example/palette.mmd` are generated: the test
suite rewrites them on every run, so they can never go stale, and a change to
them shows up as a diff to review and commit.

`scripts/demo.sh` produces the same files through the installed binary, plus
`example/pictures` (the extracted pictures) and the preview pages
`example/index.html` and `example/images.html`, built from
`scripts/preview.html`. Open either page in a browser: the diagram is inlined
and Mermaid comes from a CDN, so no toolchain is needed. The second page shows
what `--images` buys.

## The source

| File | Job |
|---|---|
| `src/xml.zig` | the small XML parser and DOM |
| `src/yed.zig` | reads yEd's GraphML flavour into the model |
| `src/model.zig` | the neutral diagram the reader and the emitter share |
| `src/shapes.zig` | yEd names to Mermaid shapes, the mapping tables |
| `src/mermaid.zig` | the emitter |
| `src/config.zig` | the front-matter block |
| `src/convert.zig` | one entry point: document in, Mermaid and pictures out |
| `src/cli.zig`, `src/options.zig`, `src/main.zig` | the command line |
| `src/tests.zig` | the test aggregator |

Tests are behaviour tests: they assert what a reader of the output would notice
(which shape, which comment, which image node), not the shape of the code.

## Releasing

See [publishing](publishing.md).
