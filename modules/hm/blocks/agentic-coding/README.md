# Cursor team default model patch

`cursor-package.nix` preserves local Agent and Ctrl+K model selections by making
Cursor's `setDefaultModel` return without applying the server default when an
active team ID exists. It also rejects the asynchronous team-admin model nudges
at startup, on new chats, during conversations, and when restoring recent chats.
Both the editor and Agent window bundles are patched.
The shared agentic-coding block and shifu use this package.

Reviewed against Cursor 3.19.13: `GetDefaultModel` returns a model, thinking model,
Max mode, and reset timestamp. Its single consumer calls `setDefaultModel` when
the reset timestamp advances (or no default has been applied before). The
response does not identify the default's source, so the patch skips this entire
server-default application for team accounts. Personal accounts retain the
original behavior. Choose your preferred model once after installing the patch;
it cannot recover a selection already overwritten.

Cursor also has three explicit team-model nudge policies:
`team_admin_model_reset_nudges`, `team_admin_smart_auto_nudge`, and
`team_admin_latest_cursor_model_impose`. These normally bypass the user's
model-nudge opt-out and can overwrite a selection after the initial default
fetch. The patch rejects them through the shared nudge gate and the separate
application-open handler. This second path was missed by the original patch.

This does not change allowed/blocked models or other admin settings. Ordinary
model recommendations still respect the user's existing model-nudge preference.

The build checks the patch locations, updates the affected integrity checksum,
and executes the actual patched handlers with mocked services to verify team,
personal-account, invalid-model, and asynchronous team-nudge behavior. An
incompatible Cursor update fails the build and requires review. Live behavior
with a team account still needs verification after rebuilding and restarting
Cursor.
