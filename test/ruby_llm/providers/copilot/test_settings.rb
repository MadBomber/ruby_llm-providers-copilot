# frozen_string_literal: true

require 'test_helper'

class TestCopilotSettings < Minitest::Test
  Settings = RubyLLM::Providers::Copilot::Settings

  def config(**values)
    RubyLLM::Configuration.new.tap do |c|
      values.each { |key, value| c.public_send(:"copilot_#{key}=", value) }
    end
  end

  def test_defaults
    settings = Settings.new(config)

    assert_equal 'copilot', settings.command
    assert_nil settings.cwd
    assert_in_delta 600.0, settings.timeout
    refute_predicate settings, :allow_all_tools?
    assert_empty settings.args
    assert_empty settings.env
    assert_nil settings.session_id
    assert_predicate settings, :resume?
  end

  def test_config_values
    settings = Settings.new(config(command: '/opt/copilot', cwd: '/tmp', timeout: 30, allow_all_tools: true,
                                   args: '--add-dir /x', env: { FOO: 1 }, resume: false))

    assert_equal '/opt/copilot', settings.command
    assert_equal '/tmp', settings.cwd
    assert_in_delta 30.0, settings.timeout
    assert_predicate settings, :allow_all_tools?
    assert_equal ['--add-dir', '/x'], settings.args
    assert_equal({ 'FOO' => '1' }, settings.env)
    refute_predicate settings, :resume?
  end

  def test_provider_options_win
    options = { copilot: { 'command' => 'c2', timeout: nil, allow_all_tools: false, session_id: 'abc' } }
    settings = Settings.new(config(command: 'c1', timeout: 5, allow_all_tools: true), options)

    assert_equal 'c2', settings.command
    assert_nil settings.timeout
    refute_predicate settings, :allow_all_tools?
    assert_equal 'abc', settings.session_id
  end

  def test_validation
    assert_nil Settings.positive_or_nil(0)
    assert_raises(ArgumentError) { Settings.namespaced({ copilot: 'nope' }) }
    assert_empty Settings.namespaced(nil)
  end
end
