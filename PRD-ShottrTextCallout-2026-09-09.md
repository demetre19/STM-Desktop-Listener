# PRD — Shottr-Parity Text Callout Tail (STM Desktop Listener native screenshot editor)

Date: 2026-09-09
Project: STM Desktop Listener (`Sources/ScreenshotEditor*.swift`)
Status: DRAFT — awaiting exact `APPROVE PRD`

## PRD

### Product summary
The native screenshot editor's Text tool becomes a Shottr-parity **callout**: a filled rounded text box that, while selected, shows a small nub flush with its edge. Pulling the nub grows a smooth, tapering, blob-like filled tail whose tip follows the pointer anywhere around the box. Until the nub is pulled, the box renders flat (no tail). The tail is one filled shape in the box color — no stroke, no arrowhead. The standalone Arrow tool is unchanged.

### Problem
- Text boxes render flat with no attached pointer by default; the current tail handle is a detached grey disc 25 px below the box, visually unrelated to the box, and the resulting tail is a hard-edged straight triangle pinned to the edge midpoint (`ScreenshotEditorRenderer.swift:289-311`).
- Users attempt to add a separate Arrow on top of the box; the first click on an existing annotation deselects and swallows the stroke (`ScreenshotEditorCanvasView.swift:225-227`), so the arrow must be drawn off to the side and dragged in.
- No smooth repositioning ("rotate") of the pointer around the box.

### Objectives
1. Text callout tail matches Shottr's look: wide curved base flowing out of the rounded rect, Bézier-smoothed sides, tapering to a rounded tip, filled in the box color.
2. Tail is discoverable: nub visible immediately after committing text (box stays selected), flush with the box edge.
3. Tail is freely repositionable: dragging the tip to any point around the box re-attaches the base to the facing side and slides it toward the tip.
4. Box is flat when the nub has never been pulled or has been returned within the box bounds.
5. Zero regression to the Arrow tool, exports, number tool, or other annotations.

### Non-goals
- Changing the standalone Arrow tool's appearance or behavior.
- A rotation handle for the text box itself.
- Multi-line text, font selection, or text box resizing changes.
- Browser-extension editor changes (the extension retains its own editor; parity target here is Shottr, per user direction).
- Drag-to-create-callout gesture (Shottr creates box first, nub afterwards — same as here).

### Target user
The app owner producing annotated screenshots for clients/docs; expects Shottr-grade polish and speed.

### Confirmed decisions (user)
- Full Shottr parity for the text callout.
- Nub appears after the box is created, flush with the box, pullable only while the box is selected.
- Box renders flat if the nub has not been moved.
- "That arrow and nothing else": only the callout tail gets this treatment; no other tail/pointer styles.

### Inferred assumptions (labelled)
- [INFERENCE] Nub is a selection affordance only: never exported, hidden when deselected.
- [INFERENCE] Returning the tip inside the box (or within a small threshold of the edge) clears the tail (`tailPoint = nil`) so the box is flat again.
- [INFERENCE] Tail base width scales with box size and tail length (Shottr-like), capped so it never exceeds ~40 % of the attached edge.
- [INFERENCE] Tail tip is rounded (small radius), not a razor point, to match the "blob" feel in the user's reference image.

## Core principles
- One filled path (rounded rect ∪ tail) so there is no visible seam between box and tail.
- Geometry is deterministic and unit-testable independent of AppKit event flow.
- Shared renderer: screen and export draw the identical path.

## User experience
1. Select Text tool (T), click canvas, type, press Return.
2. Box appears filled in the current color; it remains selected. A small circular nub (box color with white ring, ~12 px on screen) sits flush on the bottom edge center of the box.
3. Drag the nub: the moment the tip leaves the box bounds, a tail grows from the box toward the pointer. Moving the pointer around the box moves the base to the facing edge and slides it along that edge toward the tip. Release to keep.
4. Selected callout shows: box outline handles as today, plus the tail-tip nub (at the tip when a tail exists; flush on the bottom edge when flat).
5. Drag tip back inside the box → tail disappears; box flat; nub returns flush.
6. Deselect → nub hidden; export shows box + tail only.
7. Moving the box moves the tail with it (already implemented in `ScreenshotAnnotation.translate`).

## Functional requirements & acceptance criteria

FR-1 Flush nub
- Given a text annotation with `tailPoint == nil` is selected, the renderer draws a nub centered on the bottom edge midpoint of the text rect (not 25 px below).
- Hit-test radius for the nub ≥ 15 image px (existing) so it is grabbable.
- AC: `textTailHandlePosition` returns `(rect.midX, rect.maxY)` for flat callouts.

FR-2 Tail creation
- Dragging the nub sets `tailPoint`. While `tailPoint` lies inside the text rect inset by 4 px, `tailPoint` is normalized to `nil` on mouse-up (flat).
- AC: drag nub 40 px below the box → tail rendered; drag back into the box → tail gone, box flat.

FR-3 Tail geometry (Shottr blob)
- Attachment side = side of the box facing the tip (dominant axis of vector from rect center to tip, using the rect's aspect-normalized comparison so wide boxes attach top/bottom unless the tip is clearly beside them).
- Base center slides along the attached edge toward the tip's projection, clamped to leave ≥ corner radius from each corner.
- Base width `w = clamp(0.28 · edgeLength, 14, min(0.4 · edgeLength, 24 + 0.15 · tailLength))`.
- Sides are quadratic/cubic Bézier curves from base points to the tip such that the tail is concave near the base (flares into the box) and tapers to a tip of radius ≈ 2 px.
- Tail is filled with `annotation.color`, no stroke, anti-aliased, drawn in the same fill pass as the box so overlap is seamless.
- AC (pixel tests): tail pixels present outside the box on the attached side; no tail pixels on the opposite side; column widths of the tail decrease monotonically from base to tip; the tail's base row is wider than the straight-line triangle's base at the same points (proves the flare).

FR-4 Selection behavior
- Committing new or edited text keeps the annotation selected (already true) and immediately shows the nub.
- Nub and other selection chrome are drawn only when `includeSelection == true`.
- AC: `renderedImage()` output contains no nub pixels (white ring color) at the nub position.

FR-5 Arrow tool untouched
- AC: existing `ScreenshotEditorRendererTests` arrow render tests pass byte-for-byte.

FR-6 Text hit-test includes tail
- Clicking on the tail selects/moves the callout.
- AC: `annotation(at:)` returns the callout for a point on the tail midline.

## Conceptual data model
`ScreenshotAnnotation` (unchanged fields): `start`, `text`, `fontSize`, `color`, `tailPoint: CGPoint?`.
New pure geometry in `ScreenshotEditorCore.swift` (or a new `ScreenshotCalloutGeometry.swift`):
```
struct CalloutGeometry {
  static func textRect(for: ScreenshotAnnotation, textWidth: CGFloat) -> CGRect
  static func tailPath(rect: CGRect, tip: CGPoint, cornerRadius: CGFloat) -> CGPath?   // nil when tip inside rect
  static func nubPosition(rect: CGRect, tip: CGPoint?) -> CGPoint
  static func normalizedTip(rect: CGRect, tip: CGPoint) -> CGPoint?                     // nil → flat
}
```

## State model
- `flat` (`tailPoint == nil`) ⇄ `tailed` (`tailPoint` outside rect). Transition on `.textTail` drag end via `normalizedTip`.
- Selection state unchanged; nub visibility derived from selection.

## Normative runtime contracts
- Renderer MUST build the combined path once per draw: rounded rect + tail path → single `fillPath`.
- Renderer MUST reset `textPosition` before `CTLineDraw` (existing invariant).
- `mouseUp` MUST normalize `tailPoint` per FR-2.
- `textTailHandlePosition` MUST equal `CalloutGeometry.nubPosition`.

## Technical approach
- Files: `Sources/ScreenshotEditorRenderer.swift` (`drawText`, tail handle drawing at ~497-501, `textTailHandlePosition` 527-533), `Sources/ScreenshotEditorCanvasView.swift` (mouseUp normalization for `.textTail`; `annotation(at:)` tail hit-test), `Sources/ScreenshotEditorCore.swift` (geometry helpers).
- Geometry: compute attached edge, base points `b1,b2`, control points offset outward from the box along the edge normal by ~35 % of tail length and pulled toward the tip's perpendicular for the concave flare; tip drawn as a short arc of radius 2 px between the two side curves.
- No new dependencies; Core Graphics only.

## Security / safety
No credential, network, or file-path changes. No config schema change.

## Performance
Path construction is O(1) per callout; no allocations beyond one `CGMutablePath` per draw. No impact on the warm `CGDisplayStream` capture path.

## Milestones
1. Geometry helpers + unit tests (pure, no AppKit views).
2. Renderer: combined fill path, flush nub, tip nub.
3. Canvas: tail normalization on mouse-up, tail hit-testing.
4. Install via `./install.sh`, visual verification against Shottr reference.

## Implementation orchestration package
Single owner, single branch (`codex/shottr-callout-tail`), one consolidated verification batch. Recommended profile: Standard.

## Verification strategy
- `xcrun swiftc Sources/ScreenshotEditorCore.swift Sources/ScreenshotEditorRenderer.swift Tests/ScreenshotEditorRendererTests.swift -framework AppKit -o /tmp/stm-renderer-tests && /tmp/stm-renderer-tests` — existing tests plus new tail tests (FR-3 pixel checks, FR-4 no-nub-in-export, flat-vs-tailed, side attachment for 4 directions).
- `ScreenshotEditorCoreTests` compile & pass (tool order unchanged).
- `./install.sh`; open a real capture, create text, verify nub flush, pull to each of 4 sides and diagonals, drag back to flatten, export PNG and confirm no nub; compare side by side with the user's Shottr reference image.
- Arrow tool render test byte-identity.

## Risks
- Aspect-based side selection may feel wrong on very wide boxes at shallow angles → tune threshold with the visual test.
- Bézier flare may overlap text glyphs if the base is too wide → cap at 40 % of edge and confirm with test text.

## Future expansion
Tail on other shapes; drag-to-create callout; text box resize.

## Signoff criteria
All FR acceptance criteria met, tests green, installed app visually matches Shottr callout per user confirmation, Arrow tool unchanged.
