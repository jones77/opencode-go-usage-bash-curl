# `opencode-go-usage.sh`

A single-file shell script that fetches
and displays your [OpenCode Go](https://opencode.ai) usage.

Results are cached locally for 120 seconds so repeated runs don't hit the API.

## Usage

```bash
./opencode-go-usage.sh --help
```

## Dependencies

- **bash** 4.x+
- **python3** (for ISO-8601 timestamp parsing and JSON handling)
- **curl**

## Screenshot
<img width="1361" height="638" alt="Demonstration of --one-line mode and --vertical showing a poor man's usage over datetimestamp"
 src="https://github.com/user-attachments/assets/9a3ee94a-faf4-4c19-9f28-5a34f05c369f"
/>

## Setup

Copy the example env file: `cp .env.example .env`

Then edit `.env` and replace `your-api-key-here` with your actual key.
The `.env` file is `.gitignore`d which (allegedly)
will prevent it's accidental commital.

## Tests

```bash
bash test_opencode-go-usage.sh
```

The test file sources the main script through the entry-point guard.
