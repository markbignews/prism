# Screenshots

This folder is the reserved drop-in area for the screenshots used in the repository README.

## Slots

Three shots, always in this order:

| Slot | Filename | What it should show |
|---|---|---|
| 1 | `01-main.png` | **Main window.** The chat with the chapter list in the sidebar — "conversations become chapters". |
| 2 | `02-memory.png` | **Memory panel.** Timeline, people, emotional trajectory and findings in one view — "what it keeps". |
| 3 | `03-confirm.png` | **The card that asks before it acts.** A native question or approval card, buttons visible. |

### Notes per slot

- **1 — Main window.** Keep the sidebar chapter list and at least one exchange visible. This is the "what is this" shot.
- **2 — Memory panel.** The panel renders its blocks in this order: narrative timeline → people → emotional trajectory → findings. Scroll so that at least two blocks are visible; if the timeline has no recorded events yet, prefer a conversation that does.
- **3 — Question / confirmation card.** Either card makes the point:
  - the **clarification card** (`ClarificationCard`) — one question, 2–4 options plus free-text input;
  - the **timeline event review** (`NarrativeEventApprovalView`) or the **person-merge** confirmation, with the Save / "是同一人 / 分开保留" buttons visible.
  Crop so the card and its buttons are the subject rather than the whole window.

## How to use

1. Put the image files here (PNG, ideally 1600–2200 px wide).
2. Point the README at them, e.g. `Prism/assets/screenshots/01-main.png`.
3. Keep the three-slot order used on the front page.

## Conventions

- **Use fictional or invented content only.** No real names, chat logs, contacts, or anything that could identify a person.
- Window on a plain background, rounded corners acceptable; dark or light both work — just keep the three consistent.
- Capture at 2× (Retina) and avoid scaling artifacts; keep file size reasonable (the current shots are ~1 MB each at 2184×1688).
- Do not leave two sets referenced: either overwrite the files in `assets/` or move the new ones here and update the README paths.

## Current state

The front page uses `../1.png` for slot 1 and `../3.png` for slot 2. **Slot 3 has no image yet** — the README shows a text placeholder in its place, so nothing renders broken. `../2.png` (the reasoning-chain shot) is no longer used on the front page but is kept in `assets/` in case you want it back as a fourth slot.
