# frozen_string_literal: true

module RubyLLM
  module Providers
    class Copilot < Provider
      # Builds the argv for one non-interactive `copilot` run. The prompt is
      # piped on stdin; copilot has no system-prompt flag, so instructions are
      # folded into the prompt by the provider.
      class Command
        EFFORTS = %w[none minimal low medium high xhigh max].freeze

        def initialize(settings)
          @settings = settings
        end

        # @param model [String, nil] model id; "default" means the CLI's own choice
        # @param session_id [String] id for a new session (copilot lets the caller pick it)
        # @param resume_id [String, nil] session id to continue instead
        # @param effort [String, nil] one of EFFORTS
        # @return [Array<String>]
        def build(session_id:, model: nil, resume_id: nil, effort: nil)
          argv = [@settings.command, '--silent', '--output-format', 'json']
          argv.push('--model', model.to_s) if self.class.named?(model)
          argv.push(*(resume_id ? ['--resume', resume_id] : ['--session-id', session_id]))
          argv.push('--reasoning-effort', effort) if effort
          argv << '--allow-all-tools' if @settings.allow_all_tools?
          argv.concat(@settings.args)
        end

        class << self
          def named?(model)
            !(model.nil? || model.to_s.empty? || model.to_s == DEFAULT_MODEL)
          end

          # Instructions have no flag of their own, so they lead the prompt
          # of a new session.
          def prompt_with_instructions(prompt, system_prompt)
            return prompt if system_prompt.nil? || system_prompt.strip.empty?

            "<instructions>\n#{system_prompt}\n</instructions>\n\n#{prompt}"
          end
        end
      end
    end
  end
end
