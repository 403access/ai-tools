# Session sheet gallery

Offscreen renders of the macOS New Session and Retry sheets. Regenerate with:

```sh
swift build
.build/debug/OpenCodeBar --sheet-gallery docs/screenshots/session-sheets --scale 2
```

## Retry

| Image | Scenario |
| --- | --- |
| `01-same-session.png` | Retry in this session with the failed prompt and the turn's original model/agent. |
| `02-model-variant-agent.png` | Retry with a different model, the high variant and the plan agent. |
| `03-new-fork.png` | Fork the conversation before the failed prompt and retry in a new session. |
| `04-provider-error.png` | The failed turn's provider error is shown above the retry settings. |
| `05-loading-catalogs.png` | The sheet before the model and agent catalogs have loaded. |
| `06-catalog-error.png` | The model/agent catalogs could not be loaded. |
| `07-submit-error.png` | A retry submission failed and the error is shown below the settings. |
| `08-working.png` | The sheet while the retry is being submitted. |
| `09-long-content.png` | A long prompt and error message stress the sheet's wrapping and height. |
| `10-send-continue.png` | The Send “continue” shortcut fills the prompt for an interrupted turn. |
| `11-model-picker.png` | The searchable model browser opened from Retry. |

## New Session

| Image | Scenario |
| --- | --- |
| `01-existing-default.png` | Create a session in an existing project with OpenCode's default model and agent. |
| `02-model-variant-agent.png` | Create a session with a chosen model, high variant, build agent, title and first message. |
| `03-clone-repository.png` | Clone a Git repository on the Mac, then create the session in it. |
| `04-git-worktree.png` | Create an isolated Git worktree so the session's changes stay out of the main checkout. |
| `05-scheduled-start.png` | Queue the first message for a later start time. |
| `06-created-session.png` | The session exists; the user can fix the first message and retry. |
| `07-send-error.png` | Session creation or the first prompt failed. |
| `08-loading-catalogs.png` | The model and agent section while the catalogs load. |
| `09-catalog-error.png` | The catalogs could not be loaded for the selected directory. |
| `10-working.png` | The sheet while the session is being created. |
| `11-model-picker.png` | The searchable model browser opened from New Session. |