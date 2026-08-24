# opencode-go-usage

A single-file shell script that fetches and displays your
[OpenCode Go](https://opencode.ai) usage — percent remaining and
reset times for rolling, weekly, and monthly windows — with colored
progress bars in the terminal.

Results are cached locally for 120 seconds so repeated runs don't
hit the API.

## Dependencies

- **bash** 4.x+
- **python3** (for ISO-8601 timestamp parsing and JSON handling)
- **curl**

## Setup

Copy the example env file and fill in your API key:

```bash
cp .env.example .env
```

Then edit `.env` and replace `your-api-key-here` with your actual key.
The `.env` file is gitignored and will never be committed.

## Usage

```bash
./opencode-go-usage.sh
```

A few common flags:

| Flag | Effect |
|------|--------|
| `-c` | Force color (default when a terminal is detected) |
| `-1` | All periods on one line, comma-separated |
| `-s` | Compact output: percent + short date |
| `-f` | Bypass cache, always fetch from the API |
| `-n` | Show seconds remaining instead of duration strings |

Run `./opencode-go-usage.sh --help` for the full option list,
including bar styles (`-v`, `-z`, `-g`), width control, and
field/period filters.

## Tests

```bash
bash test_opencode-go-usage.sh
```

The test file sources the main script through the entry-point guard
and runs a small built-in harness. It focuses on deterministic
internals — bar cell rendering, duration formatting, argument parsing —
rather than brittle full-layout snapshots.

## License

[GNU Affero General Public License v3.0](LICENSE)
