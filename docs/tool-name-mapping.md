## 4. Copilot CLI vs Claude Code — Tool Name Mapping

| Concept                 | Copilot CLI                        | Claude Code                           |
| ----------------------- | ---------------------------------- | ------------------------------------- |
| Read file               | `view`                             | `Read`                                |
| Edit file               | `edit` / `str_replace_editor`      | `Edit`                                |
| Create file             | `create`                           | `Write`                               |
| Run shell command       | `bash`                             | `Bash`                                |
| Read async shell output | `read_bash`                        | _(not applicable — Bash is sync)_     |
| Write to async shell    | `write_bash`                       | _(not applicable)_                    |
| Stop async shell        | `stop_bash`                        | _(not applicable)_                    |
| Search file contents    | `grep`                             | `Grep`                                |
| Search file names       | `glob`                             | `Glob`                                |
| Code intelligence       | `lsp`                              | `LSP`                                 |
| Fetch URL               | `web_fetch`                        | `WebFetch`                            |
| Web search              | `web_search`                       | `WebSearch`                           |
| Ask user                | `ask_user`                         | `AskUserQuestion`                     |
| Invoke skill            | `skill`                            | `Skill`                               |
| Launch subagent         | `explore` / `task` / `code-review` | `Agent` (with `subagent_type`)        |
| Signal completion       | `task_complete`                    | _(no equivalent — implicit)_          |
| Plan mode               | `exit_plan_mode`                   | `ExitPlanMode`                        |
| Track progress          | `update_todo`                      | `TaskCreate` / `TaskUpdate`           |
| Report intent           | `report_intent`                    | _(no equivalent)_                     |
| Commit/PR progress      | `report_progress`                  | _(no equivalent — uses git directly)_ |
| Apply git patch         | `git_apply_patch`                  | _(no equivalent — uses Edit)_         |
| Self-documentation      | `fetch_copilot_cli_documentation`  | _(no equivalent)_                     |

### Key Differences

1. **Case**: Copilot uses `snake_case` (`bash`, `grep`). Claude Code uses `PascalCase` (`Bash`, `Grep`).
2. **Async shell**: Copilot has a 5-tool shell family (`bash`, `read_bash`, `write_bash`, `stop_bash`, `list_bash`). Claude Code has a single `Bash` tool with `run_in_background` flag.
3. **File ops split**: Copilot separates `view` (read) / `edit` (modify) / `create` (new). Also has `str_replace_editor` as a combined alternative. Claude Code separates `Read` / `Edit` / `Write`.
4. **Task lifecycle**: Copilot has explicit `task_complete`, `report_progress`, `update_todo`, and `report_intent` tools for autonomous workflow management. Claude Code relies on implicit conversation flow.
5. **Browser**: Copilot has built-in Playwright MCP tools (`browser_*`). Claude Code does not bundle browser automation.
6. **MCP prefix**: Copilot uses `server-name/tool-name` (slash). Claude Code uses `mcp__server__tool` (double underscore). In `.github/agents/` YAML, Copilot also accepts `github/tool` as a short alias for `github-mcp-server/tool`.
