# frozen_string_literal: true

require 'test_helper'

class TestCopilotResponse < Minitest::Test
  Response = RubyLLM::Providers::Copilot::Response

  def response
    Response.new(model: 'default', session_id: 'u1')
  end

  def test_reply_becomes_message
    r = response
    CopilotOutput.reply('pong').each { |line| r.ingest(line) }
    message = r.message

    assert_equal 'pong', message.content
    assert_equal 'u1', r.session_id
    assert_equal 'claude-sonnet-5.5', r.model_id
    assert_equal 30, message.tokens.input
    assert_equal 4, message.tokens.output
    assert_equal 18, message.tokens.cache_read
    assert_equal 12, message.tokens.cache_write
    assert_predicate message, :stopped?
    assert_equal 'u1', message.raw['session_id']
  end

  def test_streams_deltas_and_keeps_the_last_message
    r = response
    chunks = []
    lines = [CopilotOutput.delta('po'), CopilotOutput.delta(''), "noise\n", CopilotOutput.delta('ng'),
             CopilotOutput.message('pong'), CopilotOutput.message('final')]
    lines.each { |line| r.ingest(line) { |chunk| chunks << chunk } }

    assert_equal %w[po ng], chunks.map(&:content)
    assert(chunks.all?(RubyLLM::Chunk))
    assert_equal 'final', r.message.content
    assert_nil r.message.tokens.input
  end

  def test_usage_sums_models
    data = { 'accountingSnapshot' => { 'modelMetrics' => {
      'a' => { 'usage' => { 'inputTokens' => 1, 'outputTokens' => 2 } },
      'b' => { 'usage' => { 'inputTokens' => 10, 'outputTokens' => 20, 'cacheReadTokens' => 5, 'unknown' => 9 } }
    } } }

    assert_equal({ input: 11, output: 22, cache_read: 5 }, Response.usage_from(data))
    assert_nil Response.usage_from({})
  end

  def test_errors_and_missing_reply
    r = response
    r.ingest(CopilotOutput.error('not logged in'))
    error = assert_raises(RubyLLM::Providers::Copilot::Error) { r.message }

    assert_includes error.message, 'not logged in'
    run = RubyLLM::Providers::Copilot::Runner::Result.new(stdout: '', stderr: 'bad', status: FakeRunner::Status.new(3))
    error = assert_raises(RubyLLM::Providers::Copilot::Error) { response.message(run) }

    assert_includes error.message, '(3)'
    assert_includes error.message, 'bad'
  end
end
