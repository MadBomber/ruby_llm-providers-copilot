# ruby_llm-providers-copilot

A [RubyLLM](https://rubyllm.com) provider that uses the **GitHub Copilot CLI Agent Harness**
as a provider of models. Each completion runs the CLI tool `copilot` in non-interactive
mode, pipes the prompt on stdin and reads the JSON event stream from stdout.

This is deliberately *not* an isolated stand-in for a model API. The agent
keeps its own tools, MCP servers and instructions, and it works in the
current directory. Multi-turn chats resume the same Copilot session, so the
agent keeps its context between turns.

## Requirements

- Ruby 3.2 or newer
- RubyLLM 2.1 or newer
- The GitHub Copilot CLI on your PATH (`copilot --version`), logged in with
  `copilot login`. No API key is read by this gem.

## Installation

```ruby
gem 'ruby_llm-providers-copilot', require: 'ruby_llm/providers/copilot'
```

The provider registers itself as `:copilot` when required and works with no
configuration at all:

```ruby
require 'ruby_llm/providers/copilot'

chat = RubyLLM.chat(model: 'default', provider: :copilot)
puts chat.ask('Read README.md and tell me what this gem does.').content
```

## Examples

The [examples](examples/) directory holds three small demo applications. Each
prints the prompt it sends and the reply it receives, and all of them point the
agent at this gem's own root directory and only ask it to read files.

| Demo | Shows |
|---|---|
| [`01_basic.rb`](examples/01_basic.rb) | One question, one answer, with the token counts for the turn |
| [`02_session.rb`](examples/02_session.rb) | A first question that starts a Copilot session, then follow-ups that resume it; the session id is printed after each turn |
| [`03_chat_with_streaming.rb`](examples/03_chat_with_streaming.rb) | A reply streamed chunk by chunk, then an interactive chat loop on the same session |

Shared setup lives in [`common.rb`](examples/common.rb). Run a demo from the
gem root with Bundler, or directly from any directory:

```bash
bundle exec ruby examples/01_basic.rb
examples/02_session.rb
COPILOT_MODEL=auto examples/03_chat_with_streaming.rb
```

## Configuration

Every option can be set in two places. `RubyLLM.configure` sets the global
default for every chat that uses this provider:

```ruby
RubyLLM.configure do |config|
  config.copilot_command         = 'copilot'
  config.copilot_cwd             = '/path/to/project'
  config.copilot_timeout         = 600
  config.copilot_allow_all_tools = false
  config.copilot_args            = ['--add-dir', '/path/to/other/repo']
  config.copilot_env             = { 'NO_COLOR' => '1' }
  config.copilot_resume          = true
end
```

`with_provider_options` sets the same keys, without the `copilot_` prefix, for
one chat. A per-chat value wins over the global one, and the global value wins
over the built-in default:

```ruby
chat = RubyLLM.chat(model: 'default', provider: :copilot)
          .with_provider_options(copilot: { cwd: '/path/to/project', allow_all_tools: true })
```

### Options

| Option | Default | Meaning |
|---|---|---|
| `command` | `copilot` | CLI executable; a bare name is looked up on PATH, or give a full path |
| `cwd` | current directory | Directory the agent works in; relative paths in prompts, `--add-dir` and file edits all resolve here |
| `timeout` | `600` | Seconds before the whole process group is killed; `nil` or `0` disables the timeout |
| `allow_all_tools` | `false` | Pass `--allow-all-tools` so the agent runs every tool without confirmation |
| `args` | none | Extra CLI arguments appended to every invocation, as an array or a shell-style string |
| `env` | none | Extra environment variables for the CLI process, as a hash; keys and values are stringified |
| `resume` | `true` | Reuse the Copilot session across turns; `false` starts a fresh session for every completion |
| `session_id` | none | Per-chat only: continue this session regardless of the transcript (see Sessions) |

### Working directory

The agent reads and edits files relative to `cwd`, so set it to the project
you want worked on rather than relying on wherever your Ruby process happens
to run. To let the agent reach a second tree without changing `cwd`, pass
`--add-dir` through `args`.

### Tool permissions

In non-interactive mode Copilot cannot ask for confirmation, so a tool it
would normally ask about is simply not run. `allow_all_tools` lifts that for
every tool at once. For finer control leave it off and pass the CLI's own
flags through `args`, for example `--allow-tool 'shell(git status)'` or
`--deny-tool write`.

### Extra CLI arguments

`args` takes either form and hands the result straight to the CLI after the
flags this gem sets itself:

```ruby
config.copilot_args = ['--add-dir', '/other/repo', '--agent', 'reviewer']
config.copilot_args = '--add-dir /other/repo --agent reviewer'   # split with shell rules
```

Common uses are `--add-dir`, `--allow-tool`, `--deny-tool` and `--agent`. Do
not pass `--output-format`, `--model`, `--resume` or `--session-id` here, since
the gem sets those from the other options.

### Instructions

Copilot has no system-prompt flag. RubyLLM instructions
(`chat.with_instructions`) are placed at the top of the first prompt of a new
session inside an `<instructions>` block, and are not repeated on resumed
turns. Changing the instructions mid-chat therefore starts a new session.

### Timeout

`timeout` covers the whole completion, including every tool call the agent
makes along the way. When it passes, the process group gets TERM, then KILL
after a two-second grace period, and the completion raises
`RubyLLM::Providers::Copilot::TimeoutError`. Agentic work on a large
repository can legitimately take minutes, so raise it, or disable it with
`nil`, for long tasks.

## Models

The model id goes straight to `copilot --model`. The id `default` (or an empty
id) sends no `--model` flag and lets the CLI choose; `auto` lets Copilot route
each request itself.

## Sessions

Copilot lets the caller choose the session id, so every new session gets a
UUID from this gem (`--session-id`). When the transcript minus the newest
message matches what that session already saw, only the new message is sent
with `--resume <id>`. Any other shape (rewound or edited history, a cleared
chat, changed instructions) starts a fresh session with the conversation
replayed as a tagged transcript.

```ruby
chat.with_provider_options(copilot: { resume: false })      # fresh session every turn
chat.with_provider_options(copilot: { session_id: 'uuid' }) # continue a known session
chat.provider.session.id                                    # the session in use
```

## What is supported

| Feature | How |
|---|---|
| Text, system prompts, multi-turn | Instructions lead the first prompt in an `<instructions>` block; see Sessions |
| Streaming | `assistant.message_delta` events become chunks |
| `with_thinking(effort:)` | `--reasoning-effort` (none, minimal, low, medium, high, xhigh, max) |
| Token counts | Summed from the session usage checkpoint: input, output, cache read and write |
| Attachments | Noted in the prompt as `[Attached file 'name': path]`; the agent opens local files itself |
| RubyLLM tools (`with_tools`) | **Not supported**: raises `UnsupportedFeatureError`. The provider class answers `accepts_tools?` with `false` so a host application can skip attaching tools |
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
