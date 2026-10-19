# Legal notes

Back to the [README](../README.md). MPL-2.0, see [LICENSE](../LICENSE).

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
