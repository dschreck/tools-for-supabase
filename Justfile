set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

@test *ARGS:
  bash tests/lint-templates.test.sh {{ARGS}}

@lint *ARGS:
  bash lint-templates.sh {{ARGS}}
