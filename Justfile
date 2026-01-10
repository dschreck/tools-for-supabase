set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set dotenv-load := true

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
