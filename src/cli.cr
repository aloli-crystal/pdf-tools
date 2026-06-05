require "./pdf-tools"

# alolipdf — unified front-end for the ALOLI PDF tool suite.
#
# All the logic (subcommand dispatch, `help [<sub>]` / `version` /
# `doctor`, per-tool binary resolution, verbatim flag forwarding) lives
# in `AloliPdf::Dispatcher`. We intentionally do NOT use OptionParser
# here : every flag after the subcommand belongs to the target tool and
# must be passed through untouched.
exit AloliPdf::Dispatcher.run(ARGV)
