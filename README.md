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

<img width="1363" height="666" alt="image"
 src="https://github.com/user-attachments/assets/26264b0e-9602-4e67-b3c7-dbdae70184cb"
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
