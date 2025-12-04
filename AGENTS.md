# Repository Guidelines

YOU MUST FOLLOW ALL THESE RULES WHENEVER MAKING ANY CODE CHANGES!

## General
- This project is critical -- please focus!
- Don't be obsequious, sycophantic, excessively apologetic, overly verbose, or overly polite.
- Be concise—omit pleasantries, avoid repeating the prompt, and skip redundant scaffolding.
- There should always be a single canonical implementation of everything in the code.

## Planning
- Never alter the core tech stack without my explicit approval.
- Think step-by-step before making a change.
- For large changes, provide an implementation plan.
- Refactor code before making a large change.

## Code Style
- Follow bash best practices.
- Always prioritize the simplest solution over complexity.
- Code must be easy to read and understand.
- Keep code as simple as possible. Avoid unnecessary complexity.
- Follow DRY and YAGNI coding principles.
- Follow SOLID principles (e.g., single responsibility, dependency inversion) where applicable.
- DO NOT over-engineer code!
- Never duplicate code.
- Keep lines under 100 characters in length.
- Ensure all lines DO NOT have trailing whitespace.

## Variables
- Use meaningful names for variables, functions, etc. Names should reveal intent. Don't use short names for variables.

## Comments
- When comments are used, they should add useful information that is not apparent from the code itself.
- Comments should be full, gramatically-correct sentences with punctuation.
- Don't use inline comments. Instead, put the comment on the line before the relevant code.

## Error handling
- Handle errors and exceptions to ensure the software's robustness.
- Don't catch overly-broad exceptions. Instead, catch specific exceptions.
- Use exceptions rather than error codes for handling errors.
- However, don't be overly-defensive.
- Don't create alternative or backups paths for doing something.

## Functions
- Functions should be small and do one thing. They should not exceed about 50 lines.
- Function names should describe what they do.

## Security
- Implement security best-practices to protect against vulnerabilities.
- Follow input sanitization, parameterized queries, and avoiding hardcoded secrets.
- Follow web server design best practices for security.

## For bash/zsh/fish code only
- Follow all shellcheck conventions and rules.
- Handle errors gracefully.
- Use `/usr/bin/env bash` in the shebang line.
- Use `set -euo pipefail`.
- Use `[[ ]]` instead of `[ ]`.
- Use `"$()"` instead of `` ``.
- Use `"${VAR}"` instead of `"$VAR"`.
- Don't use arrays unless absolutely necessary.
- Use `printf` instead of `echo`.
- Encapsulate functionality in functions.

## Examples

<Shell>
    - Correct shebang example:
        <example>
        #!/usr/bin/env bash
        </example>

    - Correct shell options example:
        <example>
        set -euo pipefail
        </example>

    - Correct if-statement formatting example:
        <example>
        if [[ -z "${URL}" ]]; then
          exit 1
        fi
        </example>

    - Correct subshell example:
        <example>
        STATUS_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${URL}")"
        </example>
</Shell>
