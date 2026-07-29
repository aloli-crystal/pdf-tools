require "./pdf-tools/version"

# The compiled-in ALOLI tools, each exposing `Cli.run(argv) : Int32`.
# Required by their explicit `src/` paths because the shard *name* and the
# entry *file* don't always match (e.g. combine-pdf ⇒ combine_pdf).
require "combine-pdf/src/combine_pdf/cli"
require "pdf-validate/src/pdf-validate/cli"
require "pdf-signature/src/pdf-signature/cli"
require "watermark/src/watermark/cli"

require "./pdf-tools/dispatcher"

# Unified `alolipdf` front-end for the ALOLI PDF tool suite.
#
# `AloliPdf::Dispatcher` is a compiled megabinary : the ALOLI Crystal
# tools are linked in and called in-process via their `Cli.run`, while
# poppler's `info` / `fonts` stay shell-outs. One discoverable entry
# point over the whole suite. The executable lives in `src/cli.cr`.
module AloliPdf
end
