# frozen_string_literal: true

require 'ruby_llm'
require 'securerandom'
require 'ruby_llm/providers/copilot/version'
require 'ruby_llm/providers/copilot/errors'
require 'ruby_llm/providers/copilot/settings'
require 'ruby_llm/providers/copilot/command'
require 'ruby_llm/providers/copilot/transcript'
require 'ruby_llm/providers/copilot/session'
require 'ruby_llm/providers/copilot/runner'
require 'ruby_llm/providers/copilot/response'

module RubyLLM
  module Providers
    # Copilot: the GitHub Copilot CLI agent as a RubyLLM provider.
    #
    # Each completion spawns `copilot` in non-interactive mode, pipes the
    # prompt on stdin and reads its JSON event stream from stdout. The agent
    # keeps its own tools, MCP servers and instructions and works in the
    # current directory (or config.copilot_cwd). Multi-turn chats resume the
    # same session (--resume) as long as the RubyLLM transcript still matches
    # what that session has seen; otherwise a fresh session is started from
    # the whole transcript.
    #
    #   require 'ruby_llm/providers/copilot'
    #   chat = RubyLLM.chat(model: 'default', provider: :copilot)
    #   chat.ask('Summarise the README in this directory')
    class Copilot < Provider
      DEFAULT_MODEL = 'default'
      MODELS = %w[default auto].freeze
      CAPABILITIES = %w[streaming].freeze

      # Satisfies RubyLLM's protocol lookups; every request goes through
      # #complete below, never through a wire protocol.
      protocol :copilot, RubyLLM::Protocol

      class << self
        # Anything responding to #run like Runner; tests inject fakes here.
        attr_accessor :runner

        def configuration_options
          %i[copilot_command copilot_cwd copilot_timeout copilot_allow_all_tools copilot_args copilot_env
             copilot_resume]
        end

        def configuration_requirements
          []
        end

        def local?
          true
        end

        # Any id goes straight to --model, so there is no catalog to check.
        def assume_models_exist?
          true
        end

        # The agent runs its own tools; RubyLLM tools cannot be handed to it.
        # Hosts such as aia check this before attaching tools or MCP servers.
        def accepts_tools?
          false
        end

        def display_name
          'GitHub Copilot CLI'
        end

        def model_id(model)
          model.respond_to?(:id) ? model.id : model.to_s
        end

        def effort_for(thinking)
          return nil unless thinking.respond_to?(:effort) && thinking.effort

          value = thinking.effort.to_s
          Command::EFFORTS.include?(value) ? value : nil
        end

        def new_session_id
          SecureRandom.uuid
        end
      end

      attr_reader :session

      def initialize(config)
        super
        @session = Session.new
      end

      # Never contacted; the transport layer only needs a base URL.
      def api_base
        'cli://copilot'
      end

      # Messages go to the CLI as text, so there is nothing to upload or
      # convert beforehand.
      def preprocess_messages(messages, **)
        messages
      end

      def discard_missing_uploads(_messages, _error, **)
        []
      end

      # :reek:LongParameterList -- the keyword set is RubyLLM's Provider#complete contract
      def complete(messages, model:, tools: {}, provider_options: {}, schema: nil, thinking: nil,
                   temperature: nil, max_output_tokens: nil, before_request: [], **, &block)
        reject_tools!(tools)
        reject_schema!(schema)
        log_ignored(temperature:, max_output_tokens:)
        settings   = Settings.new(@config, provider_options)
        plan       = session.plan(messages, session_id: settings.session_id, resume: settings.resume?)
        transcript = Transcript.new(plan.messages)
        session_id = plan.resume_id || self.class.new_session_id
        argv       = build_argv(settings, model, plan, session_id, thinking)
        prompt     = if plan.resume?
                       transcript.prompt
                     else
                       Command.prompt_with_instructions(transcript.prompt,
                                                        transcript.system_prompt)
                     end
        before_request.each { |hook| hook.call({ argv: argv, prompt: prompt }) }
        response   = Response.new(model: model, session_id: session_id)
        run        = runner.run(argv, stdin: prompt, cwd: settings.cwd, timeout: settings.timeout,
                                      env: settings.env) do |line|
          response.ingest(line) { |chunk| block&.call(chunk) }
        end
        message = response.message(run)
        session.record(messages, message, id: response.session_id)
        message
      end

      # A static catalog: "default" sends no --model flag, "auto" lets
      # Copilot route; any other id is passed through to --model.
      def list_models
        MODELS.map { |id| static_model(id) }
      end

      private

      def runner
        self.class.runner || Runner.new
      end

      def build_argv(settings, model, plan, session_id, thinking)
        Command.new(settings).build(
          model: self.class.model_id(model),
          session_id: session_id,
          resume_id: plan.resume_id,
          effort: self.class.effort_for(thinking)
        )
      end

      def static_model(id)
        Model.new(
          id: id,
          name: "GitHub Copilot CLI (#{id})",
          provider: slug,
          capabilities: CAPABILITIES,
          modalities: { input: %w[text], output: %w[text] },
          metadata: { source: 'ruby_llm-providers-copilot' }
        )
      end

      def reject_tools!(tools)
        return if tools.nil? || tools.empty?

        raise UnsupportedFeatureError,
              'RubyLLM tools cannot be handed to the copilot CLI; the agent brings its own tools. ' \
              'Remove with_tools or choose another provider.'
      end

      def reject_schema!(schema)
        return if schema.nil?

        raise UnsupportedFeatureError, 'the copilot CLI has no structured-output option; remove with_schema'
      end

      def log_ignored(**options)
        ignored = options.compact.keys
        return if ignored.empty?

        RubyLLM.logger.debug { "copilot: ignoring #{ignored.join(', ')} (not supported by the copilot CLI)" }
      end
    end
  end
end

RubyLLM::Provider.register :copilot, RubyLLM::Providers::Copilot unless RubyLLM::Provider.resolve(:copilot)
