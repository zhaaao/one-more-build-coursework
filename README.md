# One More Build

One More Build is a five-day Godot coursework game about repairing typed visual programs for a warehouse parcel bot. The player edits node graphs, runs public cases, reads deterministic results and traces, submits each day, and receives a Career evaluation after Day 5.

## Requirements and launch

- Windows 10 or 11
- Godot Engine 4.7.2 stable
- Keyboard and mouse

Open `project.godot` in Godot 4.7.2 and press **F5 / Run Project**. No network connection, account, database, external service, or separately installed add-on is required.

## Player flow

1. Choose **Start Game** or **Load Game**.
2. Open the workstation and the **EDITOR** desktop icon.
3. Read the task requirements, create or configure nodes, and connect matching typed ports.
4. Use **Run public case** or **Run all public** to inspect the current program.
5. Read Results and Inspect, repair the graph when needed, then choose **Submit Build**.
6. Confirm the delivery and continue through all five workdays.
7. Press **Esc** during an active Career to open Pause. Pause provides Resume, Save / Load, Tutorial, unavailable Settings, and confirmed Main Menu.

An **Auto Solve** button is available as a coursework demonstration aid when you want to inspect the complete flow quickly.

## Controls

| Action | Mouse | Keyboard |
|---|---|---|
| Activate a control | Left click | Enter or Space |
| Move focus | Click | Tab / Shift+Tab or arrow keys |
| Run selected public case | Button | F5 |
| Open Pause / go back | Button where shown | Escape |
| Move a graph node | Drag | Arrow keys |
| Delete / disconnect selected content | Editor control | Delete / Alt+Delete |
| Undo / redo | Editor control | Ctrl+Z / Ctrl+Y |
| Frame or zoom graph | Editor control | Home / Ctrl+= / Ctrl+- |

Pause Save / Load contains three manual slots and one read-only autosave summary. It deliberately has no Delete action.

## Included source

- `src/core`: immutable records, graph authoring, task, execution, and sandbox logic
- `src/feature`: Workday, Career, and recovery composition
- `src/platform`: Windows persistence adapter
- `src/presentation`: workstation, editor, results, startup, day transitions, ending, Pause, and audio presentation
- `assets`: project-specific pixel art, locally synthesised music/SFX, and Silkscreen fonts

Development workflows, planning files, test infrastructure, generated reports, and marker-facing report sources are intentionally excluded from this lightweight repository.

## Verification

The submission candidate passed the explicit active-suite GdUnit4 gate: 64/64 suites and 702/702 tests, with zero errors, failures, skips, flaky cases, or test orphans. A real 1280x720 Windows interaction route also covered the five-day flow, Save/Load, Pause, Tutorial, Main Menu return, and the final Career screen. These checks do not claim peer usability or measured performance evidence; those limits are recorded in the marker-facing coursework report.

Source mirror: <https://github.com/zhaaao/one-more-build-coursework>.

## Assets, audio, and licences

- Project pixel artwork was produced for this coursework through an AI-assisted asset workflow followed by deterministic cleanup and in-engine review.
- Music and UI cues were synthesised locally from deterministic PCM recipes; no downloaded recordings or external audio generator were used.
- Silkscreen Regular and Bold are Copyright 2001 The Silkscreen Project Authors and are distributed under the SIL Open Font License 1.1. The full notice is `assets/fonts/OFL.txt`.
- Project source is distributed under the MIT licence in `LICENSE`.

Generative AI assisted planning, implementation drafts, tests, visual asset production, debugging, and report drafting. The student directed the scope, reviewed the outputs against executable evidence, supplied interaction corrections, and remains responsible for the final submission.
