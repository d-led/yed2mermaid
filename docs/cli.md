# Command line

Generated from `yed2mermaid --help` by the test suite, so it cannot drift;
the text lives in `src/cli.zig`. Back to the [README](../README.md) and
[usage](usage.md).

```text
yed2mermaid - convert yEd GraphML flowcharts to Mermaid

Usage:
  yed2mermaid [options] <file.graphml|->

Options:
  -o, --output <path>       write to <path> instead of stdout
  -d, --direction <dir>     auto (default) follows the drawing; td, lr, bt
                            and rl force one everywhere
      --style <mode>        yed (default) copies fills and lines; none drops
                            them
      --plain               shorthand for --style none
      --layout <name>       elk (default), dagre, or renderer-default to
                            leave the layout unset
      --config <json|file>  Mermaid config merged over the defaults
      --title <text>        title in the front-matter
      --no-front-matter     omit the front-matter block
      --links               emit click lines for yEd node URLs
      --images[=<dir>]      write the pictures the drawing embeds into <dir>
                            and point the diagram at them; without <dir> they
                            go to <output>-images ("auto" says the same)
      --edge-filler         give label-less edges an invisible label so they
                            keep a visible shaft (default)
      --no-edge-filler      emit label-less edges as drawn; a short one may
                            shrink to its arrow heads
      --quiet               do not print warnings
  -h, --help                show this help
  -V, --version             show the version

Reads from stdin when the input is "-".
Exit status: 0 on success, 1 for a usage error, 2 for an unreadable input
or an unwritable output.
```
