# avatar

Your agent's robot. The body is the harness (Claude Code, Codex, Cursor and others); the model builds its own head from a parts kit: color and eyes. The whole robot is one color with darker small details, a tape with the model name on the forehead, and a sticker of the model's company on the chest.

Install: send your agent

> Install this skill globally: `https://github.com/serejaris/personal-corp-os/tree/main/skills/avatar`

then, in your HQ:

```
/avatar
```

- Detects the harness and model and checks for an existing robot in `stack/avatars.json`.
- No robot yet: the model picks a head that fits its character and says why in one line.
- Saves the robot to `stack/avatars.json` and writes `avatar/robot.html` into the HQ: the robot at its desk in the HQ (files, skills shelf, MCP objects), the HQ departments around it as rooms with signs, and a small strip of four angles. HQ names go to `avatar/robot-data.js` next to the page (names, relative `.env*` paths and git state; no file contents or repository URLs); `avatar/` is added to the HQ `.gitignore`. Opens with a double click, no server or internet needed.
- A cardboard archive box with a lid sits on the floor by the left wall for every git state except `none`. An opaque door on the entrance ramp appears for `github`, `private` and `public`: locked, locked with a members-only label, or wide open with light. Local git has only the archive. Both walls remain solid; wall hooks show one key per real `.env*` file, including nested files. Keys are brass, or red for files that GitHub repositories do not ignore. This data stays in the local page and is excluded from the lesson inventory. `gh` is optional; unavailable visibility is shown as a locked door without a label.
- In a Personal Corp live class: `/avatar <join link from the lesson screen>` brings the robot into the class, where its beacon glows while the agent works. The lesson server address only ever comes in that link.

Needs Python 3. Files: `SKILL.md` (agent steps), `avatar.py` (kit, choice check, preview), `pc3live.py` (joins the live class), `robot.html` (preview player; third-party licenses in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). The skill runs only when called by command. The skill text is in Russian.

This is a copy: the skill source lives in the Personal Corp course materials and changes come from there.

Русская версия: [README.ru.md](README.ru.md)
