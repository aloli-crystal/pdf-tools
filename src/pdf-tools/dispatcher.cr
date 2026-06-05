module AloliPdf
  # The `alolipdf` dispatcher : one discoverable entry point for the whole
  # ALOLI PDF suite. Each subcommand is forwarded to the matching
  # standalone binary (combine, validate, sign/verify, watermark…),
  # inheriting stdio so the user sees the tool's own output and exit code.
  #
  # We shell out rather than link the shards together : their `pdf`
  # versions conflict (combine-pdf on 0.5.x, the validators/signer on
  # 1.x), so a single compiled megabinary isn't possible today. This
  # façade gives the unified UX now, and can become a megabinary later if
  # the versions are ever unified.
  #
  # Binary resolution per tool : `$ALOLIPDF_<TOOL>` (an explicit path)
  # first, otherwise the candidate name on `PATH`. Secrets are never
  # touched — args (incl. pdf-sign's env-var-name passphrase convention)
  # are forwarded verbatim.
  module Dispatcher
    # One `alolipdf` subcommand and the binary it drives.
    record Tool,
      key : String,
      binary : String,
      env : String,
      prepend : Array(String),
      summary : String

    TOOLS = [
      Tool.new("combine", "crystal-combine-pdf", "ALOLIPDF_COMBINE", [] of String,
        "Fusionner, numéroter, compresser ou chiffrer des PDF"),
      Tool.new("validate", "pdf-validate", "ALOLIPDF_VALIDATE", [] of String,
        "Valider la conformité PDF/A (1b, 2b, 3b) et PDF/UA"),
      Tool.new("sign", "pdf-sign", "ALOLIPDF_SIGN", ["sign"],
        "Signer un PDF (PAdES B-B → B-LTA, horodatage, LTV, PKCS#11)"),
      Tool.new("verify", "pdf-sign", "ALOLIPDF_SIGN", ["verify"],
        "Vérifier les signatures d'un PDF"),
      Tool.new("watermark", "watermark", "ALOLIPDF_WATERMARK", [] of String,
        "Apposer un filigrane sur un PDF"),
    ]

    # Runs the dispatcher against a full argv. Returns the process exit
    # code to propagate.
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
          forward(tool, argv[1..])
        else
          STDERR.puts "alolipdf : sous-commande inconnue « #{sub} »."
          STDERR.puts "Essayez `alolipdf help` (outils : #{TOOLS.map(&.key).join(", ")})."
          2
        end
      end
    end

    # Resolves a tool's binary : `$ALOLIPDF_<TOOL>` then PATH ; nil if none.
    def self.resolve(tool : Tool) : String?
      if explicit = ENV[tool.env]?
        return explicit unless explicit.empty?
      end
      Process.find_executable(tool.binary)
    end

    # Forwards `args` to the tool's binary (prefixed by its fixed
    # `prepend`, e.g. pdf-sign's `sign`/`verify`), inheriting stdio.
    def self.forward(tool : Tool, args : Array(String)) : Int32
      target = resolve(tool)
      unless target
        STDERR.puts missing(tool)
        return 2
      end
      Process.run(
        target,
        tool.prepend + args,
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit,
      ).exit_code
    end

    # `alolipdf help [<tool>]` : global banner, or delegate to the tool's
    # own `-h` when a tool is named.
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
      bin = resolve(tool)
      unless bin
        STDERR.puts missing(tool)
        return 2
      end
      Process.run(bin, ["-h"],
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit).exit_code
    end

    # `alolipdf doctor` : which underlying tools are installed.
    def self.doctor : Int32
      puts "alolipdf #{AloliPdf::VERSION} — diagnostic de la suite PDF ALOLI"
      puts ""
      all_present = true
      seen = Set(String).new
      TOOLS.each do |tool|
        next unless seen.add?(tool.binary)
        path = resolve(tool)
        if path
          puts "  ✓ #{tool.binary}  →  #{path}"
        else
          all_present = false
          puts "  ✗ #{tool.binary}  (absent ; définir $#{tool.env} ou l'installer dans le PATH)"
        end
      end
      puts ""
      puts all_present ? "Tous les outils sont disponibles." : "Des outils manquent (voir ci-dessus)."
      all_present ? 0 : 1
    end

    private def self.missing(tool : Tool) : String
      String.build do |io|
        io << "alolipdf : binaire « " << tool.binary << " » introuvable pour `" << tool.key << "`.\n"
        io << "  Installez le shard aloli-crystal correspondant, puis au choix :\n"
        io << "    • symlinkez son binaire dans le PATH ;\n"
        io << "    • ou exportez " << tool.env << "=/chemin/vers/" << tool.binary << "."
      end
    end

    private def self.banner : String
      String.build do |io|
        io << "alolipdf #{AloliPdf::VERSION} — façade unifiée de la suite PDF ALOLI\n\n"
        io << "Usage : alolipdf SOUS-COMMANDE [options propres à l'outil]\n\n"
        io << "Sous-commandes :\n"
        TOOLS.each do |tool|
          io << "  " << tool.key.ljust(10) << tool.summary << "\n"
        end
        io << "\n"
        io << "  doctor    Vérifier quels outils de la suite sont installés\n"
        io << "  help [S]  Cette aide, ou délègue à l'aide de la sous-commande S\n"
        io << "  version   Version d'alolipdf\n\n"
        io << "Tout ce qui suit la sous-commande est transmis tel quel à l'outil.\n"
        io << "Ex. : alolipdf sign -i in.pdf -o out.pdf -c cert.p12 -p VAR_ENV -l b-lt\n"
      end
    end
  end
end
