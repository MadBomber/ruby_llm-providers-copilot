# frozen_string_literal: true

require 'test_helper'

class TestCopilotProvider < Minitest::Test
  Provider = RubyLLM::Providers::Copilot

  def teardown
    Provider.runner = nil
  end

  def chat(model: 'default')
    RubyLLM.chat(model: model, provider: :copilot)
  end

  def test_registration_and_class_facts
    assert_equal Provider, RubyLLM::Provider.resolve(:copilot)
    assert_equal 'copilot', Provider.slug
    assert_predicate Provider, :local?
    assert_predicate Provider, :assume_models_exist?
    refute_predicate Provider, :accepts_tools?
    assert_empty Provider.configuration_requirements
    assert_includes RubyLLM::Configuration.options, :copilot_allow_all_tools
    refute_nil Provider::VERSION
    assert_equal %w[default auto], Provider.new(RubyLLM.config).list_models.map(&:id)
    assert_match(/\A[0-9a-f-]{36}\z/, Provider.new_session_id)
  end

  def test_single_turn_through_rubyllm_chat
    Provider.runner = FakeRunner.new(CopilotOutput.reply('pong'))
    reply = chat(model: 'gpt-5').with_instructions('Answer briefly.').ask('ping')

    assert_equal 'pong', reply.content
    call = Provider.runner.calls.first

    assert_equal %w[copilot --silent --output-format json --model gpt-5 --session-id], call[:argv][0..6]
    assert_match(/\A[0-9a-f-]{36}\z/, call[:argv][7])
    assert_equal "<instructions>\nAnswer briefly.\n</instructions>\n\nping", call[:stdin]
  end

  def test_second_turn_resumes_the_session
    Provider.runner = FakeRunner.new(CopilotOutput.reply('one'), CopilotOutput.reply('two'))
    c = chat.with_instructions('Be brief.')
    c.ask('first')
    c.ask('second')
    first, second = Provider.runner.calls
    session_id = first[:argv][first[:argv].index('--session-id') + 1]

    assert_equal %W[copilot --silent --output-format json --resume #{session_id}], second[:argv]
    assert_equal 'second', second[:stdin]
  end

  def test_rewound_history_replays_without_resume
    Provider.runner = FakeRunner.new(CopilotOutput.reply('one'), CopilotOutput.reply('two'))
    c = chat
    c.ask('first')
    c.messages.pop
    c.ask('second')
    second = Provider.runner.calls.last

    refute_includes second[:argv], '--resume'
    assert_includes second[:stdin], '<user>'
  end

  def test_streaming_yields_chunks
    Provider.runner = FakeRunner.new(CopilotOutput.reply('pong'))
    pieces = []
    reply = chat.ask('ping') { |chunk| pieces << chunk.content }

    assert_equal ['pong'], pieces
    assert_equal 'pong', reply.content
  end

  def test_unsupported_features_and_errors
    Provider.runner = FakeRunner.new(CopilotOutput.reply('ok'))
    tool = Class.new(RubyLLM::Tool) do
      description 'noop'
      def execute = 'x'
    end

    assert_raises(Provider::UnsupportedFeatureError) { chat.with_tools(tool).ask('x') }
    assert_raises(Provider::UnsupportedFeatureError) { chat.with_schema({ type: 'object' }).ask('x') }
    Provider.runner = FakeRunner.new([CopilotOutput.error('nope')])
    assert_raises(Provider::Error) { chat.ask('x') }
  end

  def test_helpers
    assert_equal 'auto', Provider.model_id('auto')
    assert_equal 'max', Provider.effort_for(Struct.new(:effort).new(:max))
    assert_nil Provider.effort_for(Struct.new(:effort).new(:silly))
  end
end
