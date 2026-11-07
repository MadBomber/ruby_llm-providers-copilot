# ruby_llm-providers-copilot

A [RubyLLM](https://rubyllm.com) provider that uses the **GitHub Copilot CLI
agent** as the model. Each completion runs `copilot` in non-interactive mode,
pipes the prompt on stdin and reads the JSON event stream from stdout.

This is deliberately *not* an isolated stand-in for a model API. The agent
keeps its own tools, MCP servers and instructions, and it works in the
current directory. Multi-turn chats resume the same Copilot session, so the
agent keeps its context between turns.

```ruby
require 'ruby_llm/providers/copilot'

chat = RubyLLM.chat(model: 'default', provider: :copilot)
chat.ask('What does the Rakefile in this directory do?')
chat.ask('Add a `lint` task to it') { |chunk| print chunk.content }
```

With [aia](https://github.com/madbomber/aia) the provider is picked from the
model prefix:

```bash
aia --model copilot/default review_prompt
aia --model claude_code/sonnet=implementer,copilot/auto=reviewer --consensus review
```

## Requirements

- Ruby 3.2 or newer
- RubyLLM 2.1 or newer
- The GitHub Copilot CLI on your PATH (`copilot --version`), logged in with
  `copilot login`. No API key is read by this gem.

## Installation

```ruby
gem 'ruby_llm-providers-copilot', require: 'ruby_llm/providers/copilot'
```

The provider registers itself as `:copilot` when required.

## Models

The part after the slash goes straight to `copilot --model`. The id `default`
(or an empty id) sends no `--model` flag; `auto` lets Copilot route.

## Sessions

Copilot lets the caller choose the session id, so every new session gets a
UUID from this gem (`--session-id`). When the transcript minus the newest
message matches what that session already saw, only the new message is sent
with `--resume <id>`. Any other shape (rewound or edited history, a cleared
chat, a changed system prompt) starts a fresh session with the conversation
replayed as a tagged transcript.

```ruby
chat.with_provider_options(copilot: { resume: false })      # fresh session every turn
chat.with_provider_options(copilot: { session_id: 'uuid' }) # continue a known session
```

## Configuration

Global options are `RubyLLM.config.copilot_*`; the same keys can be set per
chat with `with_provider_options(copilot: { ... })`.

| Option | Default | Meaning |
|---|---|---|
| `command` | `copilot` | CLI executable |
| `cwd` | current directory | Directory the agent works in |
| `timeout` | `600` | Seconds before the process group is killed; `nil` or `0` disables |
| `allow_all_tools` | `false` | Pass `--allow-all-tools` so the agent runs tools without confirmation |
| `args` | none | Extra CLI arguments, array or shell string (`--add-dir`, `--allow-tool`, `--agent`, ...) |
| `env` | none | Extra environment variables for the process |
| `resume` | `true` | Reuse the session across turns |
| `session_id` | none | Per-request only: resume this session id |

## What is supported

| Feature | How |
|---|---|
| Text, system prompts, multi-turn | Copilot has no system-prompt flag, so instructions lead the first prompt in an `<instructions>` block; see Sessions |
| Streaming | `assistant.message_delta` events become chunks |
| `with_thinking(effort:)` | `--reasoning-effort` (none, minimal, low, medium, high, xhigh, max) |
| Token counts | Summed from the session usage checkpoint: input, output, cache read and write |
| Attachments | Noted in the prompt as `[Attached file 'name': path]`; the agent opens local files itself |
| RubyLLM tools (`with_tools`) | **Not supported**: raises `UnsupportedFeatureError`. The provider class answers `accepts_tools?` with `false` so hosts such as aia can skip attaching tools |
| Structured output (`with_schema`) | **Not supported**: the CLI has no schema option |
| temperature, max tokens | Ignored (logged at debug level) |

## Safety

Without `allow_all_tools` the CLI applies its own confirmation rules, and in
non-interactive mode an unapproved tool simply is not run. Turn it on only in
a directory you are happy to let the agent change.

## Development

```bash
bundle install
asgard test_verbose       # offline: the CLI is replaced by a fake runner
asgard quality            # tests, rubocop, flog, flay, reek, ...
```
