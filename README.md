# `opencode-go-usage.sh`

A single-file shell script that fetches
and displays your [OpenCode Go](https://opencode.ai) usage.

Results are cached locally for 120 seconds so repeated runs don't hit the API.

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
./opencode-go-usage.sh --help
```

## Tests

```bash
bash test_opencode-go-usage.sh
```

The test file sources the main script through the entry-point guard
and runs a small built-in harness.

## License

[GNU Affero General Public License v3.0](LICENSE)
