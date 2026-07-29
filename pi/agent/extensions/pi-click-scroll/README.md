# pi-click-scroll

A local Pi extension that pins the composer, scrolls the transcript, expands one block at a time by click, and copies transcript text by drag.

## Use

1. Disable `npm:pi-claude-style-scroll` from `pi/agent/settings.json`.
2. Run `/reload`.
3. Click a transcript block to toggle it. Drag across transcript text and release to copy it.

Mouse capture is required, so Pi owns mouse selection while this extension is active. Copied content is plain text.

## Controls

- Mouse wheel: scroll transcript
- Left click: toggle the clicked expandable block
- Left drag: copy the selected transcript text
- `Ctrl+O`: expand or collapse all blocks; the footer shows the current state and next action
- `/click-scroll off`: restore native terminal mouse handling
- `/click-scroll on`: enable Pi mouse handling

## Configuration

Optional global config: `~/.pi/agent/extensions/pi-click-scroll/config.json`.

```json
{
  "mouseScroll": true,
  "alternateScreen": true,
  "keyboardScroll": true,
  "mouseWheelScrollRows": 3
}
```

Use `config/config.example.json` for every option.
