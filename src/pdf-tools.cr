require "./pdf-tools/version"
require "./pdf-tools/dispatcher"

# Unified `alolipdf` front-end for the ALOLI PDF tool suite.
#
# `AloliPdf::Dispatcher` maps each `alolipdf` subcommand to a standalone
# ALOLI binary (combine, validate, sign/verify, watermark…) and forwards
# to it — one discoverable entry point over the whole suite. The
# executable lives in `src/cli.cr`.
module AloliPdf
end
