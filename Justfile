set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set dotenv-load := true

@install *ARGS:
	@command -v git >/dev/null || (echo "git is required" && exit 1)
  @command -v supabase >/dev/null || (echo "supabase is required" && exit 1)
  bash scripts/install.sh {{ARGS}}

@uninstall *ARGS:
  bash scripts/uninstall.sh {{ARGS}}

@config *ARGS:
 cp .env.example .env

@test *ARGS:
  bash tests/lint-templates.test.sh {{ARGS}}
  bash tests/update-email-templates.test.sh {{ARGS}}
  bash tests/toml.test.sh {{ARGS}}

@lint *ARGS:
  bash src/lint-templates.sh {{ARGS}}

@update *ARGS:
  bash src/update-email-templates.sh {{ARGS}}

@shellcheck:
  shellcheck -x src/*.sh src/lib/*.sh tests/*.sh
