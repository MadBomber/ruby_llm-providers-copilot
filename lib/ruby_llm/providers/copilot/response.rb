# frozen_string_literal: true

require 'json'

module RubyLLM
  module Providers
    class Copilot < Provider
      # Reads `copilot --output-format json` events line by line. Message
      # deltas are streamed as Chunks, the last assistant.message is the
      # reply, and session.usage_checkpoint carries the token usage.
      class Response
        USAGE_KEYS = {
          'inputTokens' => :input, 'outputTokens' => :output,
          'cacheReadTokens' => :cache_read, 'cacheWriteTokens' => :cache_write, 'reasoningTokens' => :thinking
        }.freeze

        attr_reader :session_id, :model_id

        def initialize(model:, session_id:)
          @model      = model
          @session_id = session_id
          @content    = nil
          @usage      = nil
          @error      = nil
        end

        # @param line [String] one line of stdout
        # @yield [RubyLLM::Chunk] a streamed piece of assistant text
        # @return [Hash, nil] the parsed event, or nil for non-JSON lines
        def ingest(line)
          event = self.class.parse(line)
          return nil unless event

          data = event['data'] || {}
          case event['type']
          when 'assistant.message_delta'
            text = data['deltaContent']
            yield chunk(text) if text && !text.empty? && block_given?
          when 'assistant.message'
            @content  = data['content'].to_s
            @model_id = data['model']
          when 'session.usage_checkpoint' then @usage = self.class.usage_from(data)
          when 'error', 'session.error', 'assistant.error' then @error = (data['message'] || data['error'] || data).to_s
          end
          event
        end

        # @param run [Runner::Result, nil] used for diagnostics when no reply arrived
        # @return [RubyLLM::Message]
        def message(run = nil)
          raise Error, "copilot failed: #{@error}" if @error

          raise_without_result!(run) if @content.nil?

          Message.new(
            role: :assistant,
            content: @content,
            model: @model,
            tokens: Tokens.new(**(@usage || {})),
            finish_reason: :stop,
            raw: { 'session_id' => @session_id, 'model' => @model_id, 'usage' => @usage }
          )
        end

        class << self
          def parse(line)
            text = line.to_s.strip
            return nil unless text.start_with?('{')

            JSON.parse(text)
          rescue JSON::ParserError
            RubyLLM.logger.debug { "copilot: non-JSON output #{text.inspect}" }
            nil
          end

          # Sums the per-model usage in a usage checkpoint into Tokens kwargs.
          def usage_from(data)
            metrics = data.dig('accountingSnapshot', 'modelMetrics') || {}
            totals = Hash.new(0)
            metrics.each_value do |entry|
              (entry['usage'] || {}).each do |key, value|
                field = USAGE_KEYS[key]
                totals[field] += value.to_i if field
              end
            end
            totals.empty? ? nil : totals
          end
        end

        private

        def raise_without_result!(run)
          status = run&.status&.exitstatus
          stderr = run&.stderr.to_s.strip
          raise Error,
                "copilot exited#{" (#{status})" if status} without a reply#{": #{stderr}" unless stderr.empty?}"
        end

        def chunk(text)
          Chunk.new(role: :assistant, content: text, model: @model)
        end
      end
    end
  end
end
