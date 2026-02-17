# DungeonDraft (Prototype)

This addon drives the MVP draft flow for CMaNGOS chat command `.draft`.

## Install

- Copy `DungeonDraft` folder into your client `Interface/AddOns/`.
- Enable `DungeonDraft` on character select.

## Usage

- `/dd` opens or closes the draft panel.
- Click `Start` to begin draft.
- Pick one of 3 dungeons first.
- Pick one of 3 for spec.
- Then pick one of 3 for each armor slot round (head/shoulders/chest/hands/legs/feet).
- Finalize is automatic on the last gear pick.

## Notes

- Server implementation is still MVP/prototype quality.
- `Finalize` now creates a draft character and reports its name; relog to character select and enter on that character.
