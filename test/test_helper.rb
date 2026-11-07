# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ruby_llm/providers/copilot'
require 'minitest/autorun'
require 'json'

# Stands in for Runner: replays canned stdout lines and records each call.
class FakeRunner
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  attr_reader :calls

  def initialize(*outputs, exitstatus: 0, stderr: '')
    @outputs = outputs
    @exitstatus = exitstatus
    @stderr = stderr
    @calls = []
  end

  def run(argv, stdin: '', cwd: nil, timeout: nil, env: {})
    @calls << { argv: argv, stdin: stdin, cwd: cwd, timeout: timeout, env: env }
    lines = @outputs.shift || []
    lines.each { |line| yield line if block_given? }
    RubyLLM::Providers::Copilot::Runner::Result.new(stdout: lines.join, stderr: @stderr,
                                                    status: Status.new(@exitstatus))
  end
end

# JSON lines shaped like `copilot --output-format json` output.
module CopilotOutput
  module_function

  def line(type, data)
    "#{JSON.generate('type' => type, 'data' => data, 'id' => 'e1', 'timestamp' => '2026-11-07T03:00:00Z')}\n"
  end

  def delta(text)
    line('assistant.message_delta', 'messageId' => 'm1', 'deltaContent' => text)
  end

  def message(text, model: 'claude-sonnet-5.5')
    line('assistant.message', 'messageId' => 'm1', 'content' => text, 'model' => model, 'toolRequests' => [])
  end

  def usage(input: 30, output: 4, cache_read: 18, cache_write: 12, model: 'claude-sonnet-5.5')
    line('session.usage_checkpoint', 'totalPremiumRequests' => 1, 'accountingSnapshot' => {
           'modelMetrics' => { model => { 'usage' => {
             'inputTokens' => input, 'outputTokens' => output, 'cacheReadTokens' => cache_read,
             'cacheWriteTokens' => cache_write, 'reasoningTokens' => 0
           } } }
         })
  end

  def error(text)
    line('error', 'message' => text)
  end

  def reply(text)
    [line('session.tools_updated', 'model' => 'claude-sonnet-5.5'), delta(text), message(text), usage,
     line('assistant.idle', {})]
  end
end

def user_message(text, **)
  RubyLLM::Message.new(role: :user, content: text, **)
end

def assistant_message(text)
  RubyLLM::Message.new(role: :assistant, content: text)
end

def system_message(text)
  RubyLLM::Message.new(role: :system, content: text)
end
