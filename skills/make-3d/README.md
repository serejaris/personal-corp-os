# make-3d

[![en](https://img.shields.io/badge/lang-en-blue.svg)](README.md)
[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

Makes a 3D model for your scene: an object, a room, a robot, an office. Instead of iterating on one model, it builds several variants and shows them side by side. Use it when you know what the model must show and which states it has, but not what it should look like.

```
/make-3d
```

Or ask: "make variants of this model", "how could this look in 3D".

- Reads the scene: source, build command, where objects are drawn, the live page. Sends you a snapshot of the scene as it is now.
- Builds one demo data set that contains every state of the model.
- Gives each variant its own copy of the scene, port and build cache. Your scene stays untouched until you pick a variant.
- Runs one executor per variant in parallel (Codex CLI by default, a subagent otherwise).
- Every variant returns the same sheets with the same camera: `general.png` (whole scene), `states.png` (grid of states with captions), `detail.png` (close-up of the detail that decides whether the model reads).
- Sends the sheets to the chat as pictures, then a short comparison and a recommendation. You pick.
- Moves the chosen variant into your scene on real data, adds tests for the state rules and sends the final sheets.

The scene shows facts, not content: file names and state flags. File contents and repository addresses never appear. The skill text is in Russian.
