# frozen_string_literal: true

require 'test_helper'

class TestCopilotCommand < Minitest::Test
  Command = RubyLLM::Providers::Copilot::Command
  Settings = RubyLLM::Providers::Copilot::Settings

  def command(provider_options = {})
    Command.new(Settings.new(RubyLLM::Configuration.new, provider_options))
  end

  def test_new_session
    assert_equal %w[copilot --silent --output-format json --session-id u1], command.build(session_id: 'u1')
  end

  def test_new_session_with_everything
    argv = command(copilot: { allow_all_tools: true, args: ['--add-dir', '/x'] })
           .build(session_id: 'u1', model: 'gpt-5', effort: 'high')
    expected = ['copilot', '--silent', '--output-format', 'json', '--model', 'gpt-5', '--session-id', 'u1',
                '--reasoning-effort', 'high', '--allow-all-tools', '--add-dir', '/x']

    assert_equal expected, argv
  end

  def test_resume
    argv = command.build(session_id: 'ignored', resume_id: 'r1', model: 'default')

    assert_equal %w[copilot --silent --output-format json --resume r1], argv
  end

  def test_instructions_lead_the_prompt
    assert_equal 'hi', Command.prompt_with_instructions('hi', nil)
    assert_equal 'hi', Command.prompt_with_instructions('hi', '  ')
    assert_equal "<instructions>\nBe terse.\n</instructions>\n\nhi", Command.prompt_with_instructions('hi', 'Be terse.')
  end
end
