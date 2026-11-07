# frozen_string_literal: true

require 'shellwords'

module RubyLLM
  module Providers
    class Copilot < Provider
      # The settings for one completion. Each value comes from, in order of
      # precedence, chat.with_provider_options(copilot: {...}), the
      # RubyLLM.config.copilot_* option, then the default here.
      class Settings
        DEFAULT_COMMAND = 'copilot'
        DEFAULT_TIMEOUT = 600

        attr_reader :command, :cwd, :timeout, :args, :env, :session_id

        def initialize(config, provider_options = {})
          opts = self.class.namespaced(provider_options)
          @command         = opts.fetch(:command) { config.copilot_command } || DEFAULT_COMMAND
          @cwd             = opts.fetch(:cwd) { config.copilot_cwd }
          @timeout         = self.class.positive_or_nil(opts.fetch(:timeout) { timeout_default(config) })
          @allow_all_tools = opts.fetch(:allow_all_tools) { config.copilot_allow_all_tools }
          @args            = self.class.split_args(opts.fetch(:args) { config.copilot_args })
          @env             = self.class.stringify(opts.fetch(:env) { config.copilot_env })
          @session_id      = opts[:session_id]
          @resume          = opts.fetch(:resume) { config.copilot_resume.nil? || config.copilot_resume }
        end

        # True when the agent may run every tool without confirmation.
        def allow_all_tools?
          @allow_all_tools ? true : false
        end

        # False when every completion must start a fresh CLI session.
        def resume?
          @resume ? true : false
        end

        class << self
          # The copilot: sub-hash of provider_options with symbol keys.
          def namespaced(provider_options)
            return {} unless provider_options.is_a?(Hash)

            raw = provider_options[:copilot] || provider_options['copilot'] || {}
            raise ArgumentError, 'provider_options[:copilot] must be a Hash' unless raw.is_a?(Hash)

            raw.transform_keys(&:to_sym)
          end

          # A positive number of seconds, or nil for "no timeout".
          def positive_or_nil(value)
            return nil if value.nil?

            number = Float(value)
            number.positive? ? number : nil
          end

          # Extra CLI arguments given as an array or a shell-style string.
          def split_args(value)
            case value
            when nil then []
            when String then Shellwords.split(value)
            else Array(value).map(&:to_s)
            end
          end

          def stringify(value)
            (value || {}).to_h.to_h { |key, item| [key.to_s, item.to_s] }
          end
        end

        private

        def timeout_default(config)
          config.copilot_timeout.nil? ? DEFAULT_TIMEOUT : config.copilot_timeout
        end
      end
    end
  end
end
