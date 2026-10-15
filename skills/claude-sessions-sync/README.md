# claude-sessions-sync

Sync Claude Code session records between two Anthropic accounts in the Claude desktop app on macOS.

## The problem it solves

The desktop app stores the session list per account + organization in
`~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<orgUuid>/local_*.json`
and lists only the current pair. Buy a second account, switch the login — and the
picker goes almost empty, even though nothing was deleted. Transcripts
(`~/.claude/projects/`) are shared across accounts; only the records are filed
per account+org.

This skill mirrors the records between the two account folders
(bidirectional, newest-wins), merges archive flags and deleted markers, and
walks you through the safe-quit procedure — the app must be fully closed
while the files move.

Typical loop when you juggle two accounts because of usage limits:

1. Ask the agent to sync sessions (this skill).
2. Switch the login in the app.
3. All sessions are in the picker again.

## Install (single skill)

```
https://github.com/serejaris/personal-corp-os/tree/main/skills/claude-sessions-sync
```

## More

Background write-up: [Moving 275 Claude Code sessions to a second account](https://sereja.tech/blog/claude-code-sessions-between-accounts/)
