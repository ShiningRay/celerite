require "./bridge/client"

module Celerite
  # Single entry point for Gemfile evaluation (roadmap L162, slice F5).
  #
  # Every production caller that needs a Gemfile evaluation — the plain
  # evaluation, the `gemspec` paths it loaded, or its `celerite-eval-v1`
  # fingerprint — goes through `fetch`. It is the only place that builds an
  # `evaluate_batch` request, so a command cannot grow a second, divergent
  # evaluation path again; `Bridge::Client#evaluate_gemfile` and
  # `#evaluate_batch` stay as compatible low-level wrappers for specs and
  # external callers.
  #
  # `fetch` asks for the whole cacheable evaluation surface in one request:
  # `fingerprint` (slice F1) and `gemspecs` (slice S2). Both are produced from
  # the same single `Bundler::Dsl#eval_gemfile` run the bridge already performs
  # for the evaluation itself, so carrying them costs no second evaluation and
  # no extra RPC; they are what let `EvaluationCache`/`EvalCacheStore` verify a
  # later reuse (F2/F4) and what makes a later `gemspec` lookup free. The
  # fingerprint state (`deterministic`/`unknown`/`broken`, slice F3) is
  # returned untouched: withholding a reuse is the cache's decision, never this
  # entry's.
  #
  # The plugin DSL is a *different* evaluation (`Bundler::Plugin::DSL`, which
  # ignores `gem` lines and raises `PluginGemfileError` for unknown methods), so
  # it stays a distinct bridge op; `plugin_names` wraps it here so callers
  # still have one place to ask "evaluate this Gemfile somehow".
  module GemfileEvaluator
    # Sections `assets/bridge/server.rb#op_evaluate_batch` can append today.
    KNOWN_SECTIONS = ["fingerprint", "gemspecs"]

    # One command's evaluation surface. The `sections` argument only validates
    # the caller's request against `KNOWN_SECTIONS`: the request always carries
    # both sections, so the wrappers below strip what a caller did not ask for.
    def self.fetch(path : String, sections : Array(String) = [] of String,
                   client : Bridge::Client? = nil) : Bridge::BatchGemfileEvaluation
      unknown = sections.reject { |section| KNOWN_SECTIONS.includes?(section) }
      unless unknown.empty?
        raise ArgumentError.new("unknown Gemfile evaluation section(s): #{unknown.join(", ")}")
      end

      # `gemspecs` and `fingerprint` are both free once the Gemfile has been
      # evaluated, and both are cache evidence: asking for them unconditionally
      # is what turns "one command, one evaluation" into "one command, one
      # request" even when the call sites need different slices.
      bridge = client || Bridge::Client.shared
      bridge.evaluate_batch(path, ["fingerprint", "gemspecs"])
    end

    # The evaluation every command consumes.
    def self.evaluation(path : String, client : Bridge::Client? = nil) : Bridge::GemfileEvaluation
      fetch(path, client: client).evaluation
    end

    # Absolute paths of the gemspecs loaded by `gemspec` directives, in DSL
    # order (reference: `Bundler::Dsl#gemspecs.map(&:loaded_from)`). Empty when
    # the Gemfile declares none.
    def self.gemspecs(path : String, client : Bridge::Client? = nil) : Array(String)
      fetch(path, client: client).gemspecs || [] of String
    end

    def self.fingerprint(path : String, client : Bridge::Client? = nil) : Bridge::EvalFingerprint?
      fetch(path, client: client).fingerprint
    end

    # Names the `Bundler::Plugin::DSL` would pre-install, in declaration order.
    # Raises `Bridge::BridgeError` for Gemfile errors; the envelope carries the
    # reference `status_code` (29 plugin gemfile errors, 15 invalid options,
    # 4 other Gemfile errors), so callers propagate it unchanged.
    def self.plugin_names(path : String, client : Bridge::Client? = nil) : Array(String)
      bridge = client || Bridge::Client.shared
      bridge.plugin_gemfile_eval(path)["plugin_names"].as_a.map(&.as_s)
    end
  end
end
