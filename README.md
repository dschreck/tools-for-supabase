# Supabase Tools

> "I have to have my tools!"
>
> \- Dennis Reynolds, _It's Always Sunny in Philadelphia_
>
> <http://youtube.com/watch?v=gWGTehbT2LQ>

Collection of some tools I use for Supabase projects.

## Requirements

- `bash` and standard Unix tools (`awk`, `grep`, `sed`, `find`, `sort`, `wc`)
- `curl` (for `src/update-email-templates.sh`)
- `just` (for the `Justfile` recipes and `.env` loading)

Debian/Ubuntu

```bash
sudo apt-get update && sudo apt-get install -y curl just
```

Arch

```bash
sudo pacman -Syu --noconfirm curl just
```

## Project Layout

- `src/` scripts and helpers
- `src/lib/` shared shell functions
- `tests/` test scripts and fixtures

## `src/lint-templates.sh`

- Checks the template files you have to ensure you dont have a bad variable, as supabase really doesn't tell you much about why it fails

### Usage

```bash
just lint --no-emoji --file example/templates/confirmation.html
```

### Tests

```bash
just test
just test "invalid variable"
```

## `src/update-email-templates.sh`

- Updates Supabase Auth email templates via the Management API.
- Reads template subjects/paths from `supabase/config.toml` when available.
- Only uploads templates that have both a subject and a template path; incomplete entries are skipped with a warning.

```bash
SUPABASE_ACCESS_TOKEN=your-token SUPABASE_PROJECT_REF=your-project-ref \
  just update

# Use config.toml if present or pass it explicitly:
SUPABASE_ACCESS_TOKEN=your-token SUPABASE_PROJECT_REF=your-project-ref \
  just update --config supabase/config.toml

# If you ran `supabase link`, the script can read .supabase/project-ref:
SUPABASE_ACCESS_TOKEN=your-token \
  just update --config supabase/config.toml

# Or override the project ref directly:
SUPABASE_ACCESS_TOKEN=your-token \
  just update --project-ref your-project-ref

# If no config is available, provide subjects and template paths:
SUPABASE_ACCESS_TOKEN=your-token SUPABASE_PROJECT_REF=your-project-ref \
  just update \
  --confirmation-subject "Confirm your account" \
  --confirmation-template supabase/templates/confirmation.html \
  --recovery-subject "Reset your password" \
  --recovery-template supabase/templates/recovery.html \
  --magic-link-subject "Magic link sign-in" \
  --magic-link-template supabase/templates/magiclink.html
```

Example config snippet:

```toml
[auth.email.template.confirmation]
subject = "Confirm your account"
content_path = "./supabase/templates/confirmation.html"

[auth.email.template.recovery]
subject = "Reset your password"
content_path = "./supabase/templates/recovery.html"

[auth.email.template.magic_link]
subject = "Magic link sign-in"
content_path = "./supabase/templates/magiclink.html"
```

Use `.env.example` as a reference for required variables.

The `Justfile` loads `.env` automatically (`set dotenv-load := true`). To use a different env file:

```bash
just --dotenv-filename .env.local update --config supabase/config.toml
```

## About
