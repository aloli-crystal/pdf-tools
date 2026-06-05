module AloliPdf
  # The `alolipdf` dispatcher : one discoverable entry point for the whole
  # ALOLI PDF suite.
  #
  # Now a genuine **compiled megabinary**: the ALOLI Crystal tools
  # (combine, validate, sign/verify, watermark) are linked in and invoked
  # *in-process* via each tool's `Cli.run(argv) : Int32` entry point — no
  # child process, no separate binaries to install. This became possible
  # once the whole suite was levelled onto `pdf` 1.x.
  #
  # External, non-ALOLI tools (poppler's `pdfinfo` / `pdffonts`) are not
  # ours to compile, so `info` / `fonts` stay **shell-outs**, resolved via
  # `$ALOLIPDF_<TOOL>` then `PATH`. The dispatcher is therefore hybrid.
  #
  # Secrets are never touched : args (incl. pdf-sign's env-var-name
  # passphrase convention) are forwarded verbatim.
  module Dispatcher
    alias Runner = Proc(Array(String), Int32)

    # One `alolipdf` subcommand. Exactly one of `runner` (in-process,
    # compiled-in ALOLI tool) or `binary` (external shell-out tool) is set.
    record Tool,
      key : String,
      summary : String,
      runner : Runner?,
      binary : String?,
      env : String?

    TOOLS = [
      Tool.new("combine", "Fusionner, numéroter, compresser ou chiffrer des PDF",
        ->(a : Array(String)) { CombinePDF::Cli.run(a) }, nil, nil),
      Tool.new("validate", "Valider la conformité PDF/A (1b, 2b, 3b) et PDF/UA",
        ->(a : Array(String)) { PDF::Validate::CLI.run(a) }, nil, nil),
      Tool.new("sign", "Signer un PDF (PAdES B-B → B-LTA, horodatage, LTV, PKCS#11)",
        ->(a : Array(String)) { PDF::Signature::Cli.run(["sign"] + a) }, nil, nil),
      Tool.new("verify", "Vérifier les signatures d'un PDF",
        ->(a : Array(String)) { PDF::Signature::Cli.run(["verify"] + a) }, nil, nil),
      Tool.new("watermark", "Apposer un filigrane sur un PDF",
        ->(a : Array(String)) { Watermark::Cli.run(a) }, nil, nil),
      Tool.new("info", "Afficher les métadonnées d'un PDF (titre, dates, pages, version…)",
        nil, "pdfinfo", "ALOLIPDF_INFO"),
      Tool.new("fonts", "Lister les fontes d'un PDF (type, encodage, embarquée, subset)",
        nil, "pdffonts", "ALOLIPDF_FONTS"),
      Tool.new("detach", "Lister et extraire les fichiers attachés d'un PDF (--list, --save)",
        nil, "pdfdetach", "ALOLIPDF_DETACH"),
      Tool.new("images", "Lister et extraire les images d'un PDF (--list, --save-all)",
        nil, "pdfimages", "ALOLIPDF_IMAGES"),
      Tool.new("attach", "Joindre un fichier à un PDF (/EmbeddedFiles + /AF, Factur-X)",
        nil, "pdfattach", "ALOLIPDF_ATTACH"),
      Tool.new("tops", "Convertir un PDF en PostScript / EPS (relais ghostscript)",
        nil, "pdftops", "ALOLIPDF_TOPS"),
    ]

    # Runs the dispatcher against a full argv. Returns the exit code.
    def self.run(argv : Array(String)) : Int32
      case sub = argv[0]?
      when nil, "help", "-h", "--help"
        help(argv[1]?)
      when "version", "-v", "--version"
        puts "alolipdf #{AloliPdf::VERSION}"
        0
      when "doctor"
        doctor
      else
        tool = TOOLS.find { |entry| entry.key == sub }
        if tool
          dispatch(tool, argv[1..])
        else
          STDERR.puts "alolipdf : sous-commande inconnue « #{sub} »."
          STDERR.puts "Essayez `alolipdf help` (outils : #{TOOLS.map(&.key).join(", ")})."
          2
        end
      end
    end

    # In-process call for compiled-in tools, shell-out for external ones.
    def self.dispatch(tool : Tool, args : Array(String)) : Int32
      if runner = tool.runner
        runner.call(args)
      else
        forward(tool, args)
      end
    end

    # Shell-out for external (non-ALOLI) tools : `$ALOLIPDF_<TOOL>` then
    # `PATH`, inheriting stdio. Only reached for `info` / `fonts`.
    def self.forward(tool : Tool, args : Array(String)) : Int32
      target = resolve(tool)
      unless target
        STDERR.puts missing(tool)
        return 2
      end
      Process.run(
        target,
        args,
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit,
      ).exit_code
    end

    # Resolves an external tool's binary : `$ALOLIPDF_<TOOL>` then PATH.
    def self.resolve(tool : Tool) : String?
      if (env = tool.env) && (explicit = ENV[env]?)
        return explicit unless explicit.empty?
      end
      if name = tool.binary
        return Process.find_executable(name)
      end
      nil
    end

    # `alolipdf help [<tool>]` : global banner, or delegate to the tool's
    # own `-h` (in-process or shell-out).
    def self.help(target : String?) : Int32
      if target.nil? || target.empty?
        puts banner
        return 0
      end
      tool = TOOLS.find { |entry| entry.key == target }
      unless tool
        STDERR.puts "alolipdf : pas d'aide pour « #{target} » (outils : #{TOOLS.map(&.key).join(", ")})."
        return 2
      end
      dispatch(tool, ["-h"])
    end

    # `alolipdf doctor` : compiled-in tools are always present ; external
    # tools (info/fonts) are checked on PATH.
    def self.doctor : Int32
      puts "alolipdf #{AloliPdf::VERSION} — diagnostic de la suite PDF ALOLI"
      puts ""
      all_present = true
      TOOLS.each do |tool|
        if tool.runner
          puts "  ✓ #{tool.key.ljust(10)} compilé dans alolipdf (in-process)"
        elsif path = resolve(tool)
          puts "  ✓ #{tool.key.ljust(10)} #{tool.binary} → #{path}"
        else
          all_present = false
          puts "  ✗ #{tool.key.ljust(10)} #{tool.binary} absent (définir $#{tool.env} ou l'installer dans le PATH)"
        end
      end
      puts ""
      puts all_present ? "Tous les outils sont disponibles." : "Outil(s) externe(s) manquant(s) — voir ci-dessus."
      all_present ? 0 : 1
    end

    private def self.missing(tool : Tool) : String
      String.build do |io|
        io << "alolipdf : outil externe « " << tool.binary << " » introuvable pour `" << tool.key << "`.\n"
        io << "  C'est un outil poppler (non ALOLI). Installez-le (`brew install poppler`,\n"
        io << "  `apt install poppler-utils`…) ou exportez $" << tool.env << "=/chemin/vers/" << tool.binary << "."
      end
    end

    private def self.banner : String
      String.build do |io|
        io << "alolipdf #{AloliPdf::VERSION} — suite PDF ALOLI (binaire unifié)\n\n"
        io << "Usage : alolipdf SOUS-COMMANDE [options propres à l'outil]\n\n"
        io << "Sous-commandes :\n"
        TOOLS.each do |tool|
          tag = tool.runner ? "" : " (externe)"
          io << "  " << tool.key.ljust(10) << tool.summary << tag << "\n"
        end
        io << "\n"
        io << "  doctor    Vérifier quels outils sont disponibles\n"
        io << "  help [S]  Cette aide, ou délègue à l'aide de la sous-commande S\n"
        io << "  version   Version d'alolipdf\n\n"
        io << "Tout ce qui suit la sous-commande est transmis tel quel à l'outil.\n"
        io << "Ex. : alolipdf sign -i in.pdf -o out.pdf -c cert.p12 -p VAR_ENV -l b-lt\n"
      end
    end
  end
end
