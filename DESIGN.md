---
name: Deckle
description: A quiet, tactile macOS menu bar studio for making screens feel like paper.
colors:
  brand-rust: "#B34A21"
  brand-rust-dark: "#E69163"
  system-accent: "#007AFF"
  success-green: "#34C759"
  warning-orange: "#FF9500"
  danger-red: "#FF3B30"
  sample-ink: "#29241C"
  window-light: "#F5F5F7"
  surface-light: "#FFFFFF"
  label-light: "#1D1D1F"
  secondary-label-light: "#6E6E73"
  hairline-light: "#00000014"
  window-dark: "#1C1C1E"
  surface-dark: "#2C2C2E"
  label-dark: "#F5F5F7"
  secondary-label-dark: "#AEAEB2"
  hairline-dark: "#FFFFFF14"
typography:
  paper-name:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "27px"
    fontWeight: 500
  wordmark:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "23px"
    fontWeight: 500
  section-serif:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "15px"
    fontWeight: 500
  header:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: 700
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "11px"
    fontWeight: 500
  micro:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "10px"
    fontWeight: 400
  meta-mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "9px"
    fontWeight: 600
    letterSpacing: "1.8px"
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "11px"
    fontWeight: 500
rounded:
  thumbnail: "3px"
  sample: "5px"
  setup: "6px"
  track: "8px"
  badge: "10px"
  search: "12px"
  banner: "14px"
  drawer: "16px"
  capsule: "999px"
spacing:
  track: "3px"
  compact: "4px"
  control: "6px"
  item: "8px"
  setup: "9px"
  group: "10px"
  section: "12px"
  shell: "14px"
  sample: "16px"
  editor: "18px"
components:
  mode-tab:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.body}"
    rounded: "{rounded.setup}"
    padding: "7px 0"
  search-field:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.body}"
    rounded: "{rounded.search}"
    padding: "8px 10px"
  paper-sample:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.sample-ink}"
    typography: "{typography.paper-name}"
    rounded: "{rounded.sample}"
    padding: "16px"
    width: "342px"
    height: "148px"
  paper-card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.sample}"
    padding: "8px"
    width: "108px"
  setup-card:
    backgroundColor: "{colors.window-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.setup}"
    padding: "9px"
  filter-chip:
    backgroundColor: "{colors.window-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
  filter-chip-selected:
    backgroundColor: "{colors.brand-rust}"
    textColor: "{colors.surface-light}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
  control-tab-selected:
    backgroundColor: "{colors.system-accent}"
    textColor: "{colors.surface-light}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "6px 10px"
---

# Design System: Deckle

This document describes the interface as implemented in `Sources/Deckle`. When code and this document disagree, update whichever is wrong in the same change.

## Overview

**Creative North Star: "The Quiet Paper Studio"**

Deckle is opened briefly while someone is reading, writing, or working across one or more displays. Its controls should feel like well-kept tools on a calm desk: familiar, precise, tactile, and ready to disappear as soon as the paper is chosen.

The interface is a restrained macOS product surface. System materials and semantic colors provide light/dark adaptation; Deckle Rust marks selection. Actual procedural paper samples carry the visual identity. Dense controls remain legible without turning the popover into a dashboard.

Deckle rejects ornamental glassmorphism, neon utility palettes, oversized marketing typography, nested card stacks, and motion that delays a task.

**Key Characteristics:**

- System-native and immediately understandable
- Quiet neutral surfaces with one brand accent
- Paper samples as the dominant visual material
- Compact controls with explicit labels and state
- One focused mode at a time instead of stacking every section vertically
- Fast, interruptible transitions

**The One Mode Rule.** The menu shows exactly one of *Your desk*, *Library*, *Pets*, or *Controls and settings*. Searching and browsing live in Library; opening the controls replaces the current content rather than stacking a drawer over it.

**The Honest Material Rule.** The popover background is `windowBackgroundColor` at 96% opacity. Content surfaces inside it are opaque or strongly tonal. Empty translucent regions below the footer are a sizing bug.

## Colors

In SwiftUI, system semantic colors are the runtime source of truth. The fixed neutral values in the front matter are cross-tool approximations for documentation and generated components.

### Accents

- **Deckle Rust** (`brand-rust`, `brand-rust-dark`): `StudioStyle.rust`, sRGB (0.70, 0.29, 0.13) in light appearance and (0.90, 0.57, 0.39) in dark. It is applied as the menu's `.tint` and marks the selected paper card, selected desk setup, selected category chip, the Paper Mill button, the "Your desk" link, the search-result count, the showing-status dot, and the update dot on the controls button.
- **System accent** (`system-accent`, blue by default, follows the user's macOS accent color): `Color.accentColor` for the Update capsule and banner badge, the focused search field, the controls panel icon and selected control tab, and Paper Mill's prominent buttons and sliders.

### Semantic colors

- **Success Green** (`success-green`): Paper Mill's Stop Preview button while a preview is live, the "Up to date" badge, and Good/Excellent retention grades.
- **Warning Orange** (`warning-orange`): the snooze countdown heading, update failures, Reduced contrast grades, and Paper Mill's contrast warning.
- **Danger Red** (`danger-red`): Heavy contrast loss grades, the destructive Delete button, and the Settings tab's Quit Deckle button.

### Neutral

- **Quiet Window** (`window-light`, `window-dark`): popover background.
- **Paper Surface** (`surface-light`, `surface-dark`): `controlBackgroundColor` surfaces: search field, banners, selected mode tab, control panel, unselected paper cards.
- **Ink Label** (`label-light`, `label-dark`): primary text.
- **Soft Graphite** (`secondary-label-light`, `secondary-label-dark`): descriptions, metadata, inactive labels, and help copy.
- **Hairline** (`hairline-light`, `hairline-dark`): primary color at 4–15% opacity for containment.
- **Sample Ink** (`sample-ink`): text over light paper samples, sRGB (0.16, 0.14, 0.11); dark samples use white.

**The Semantic State Rule.** Green means live or successful, orange means caution or snoozed, and red means destructive or heavy loss. Do not reuse them decoratively.

## Typography

**Serif:** the system serif (`.serif` design, New York) for the wordmark, paper names, and the Desk setups heading.
**Sans:** the Apple system font for all controls and copy.
**Mono:** the system monospaced design for changing values and sample metadata.

### Hierarchy

- **Paper name** (serif 27, medium): the selected paper on the desk sample; scales down to 70% to stay on one line.
- **Wordmark** (serif 23, medium): "Deckle" in the menu header.
- **Section serif** (serif 15, medium): "Desk setups".
- **Header** (13, bold): "Paper library" and "Search Results".
- **Body** (12): mode tabs, paper card names (semibold), slider labels, setup names.
- **Label** (11): chips, control tabs, header buttons, desk sample subtitle, status text.
- **Micro** (9–10): tagline, footer, setup status, card tags, notes.
- **Meta mono** (mono 9, semibold, 1.8-point tracking, uppercase): "ON YOUR DESK" / "PAPER SAMPLE · 22%" on the desk sample.
- **Mono** (mono 9–11): percentages, counts, and the ⌥⌘P badge.

**The Stable Number Rule.** Every changing percentage, timer, count, and comfort metric uses monospaced or monospaced-digit typography so controls do not shift.

**The Native Voice Rule.** Buttons use sentence case and short verbs. Uppercase is reserved for the desk sample's metadata line.

## Elevation

Surfaces are separated by system background roles and low-opacity hairlines, not shadows. Shadows appear in exactly three places:

- The selected paper card's white checkmark: black at 40%, 2-point radius, so it reads over light samples.
- The Update capsule: system accent at 30%, 3-point radius, 1-point offset.
- The update banner: system accent at 8%, 6-point radius, 2-point offset.

Pet artwork carries its own paper shadows (see Pets). They are part of the illustration, not interface elevation.

## Components

### Popover shell

- **Width:** fixed at 370 points; **padding:** 14 points; **section spacing:** 14 points.
- **Sizing:** `MenuPopover` measures the content and resizes the native MenuBarExtra window to fit it, keeping the top edge anchored and clamping to the screen's visible frame. Content taller than the visible frame scrolls.
- **Header:** the serif wordmark and 10-point tagline "A softer place to work.", a bordered small **Paper Mill** / **Close Mill** button with a scissors icon, and a 28-point controls button (sliders icon, or an xmark on a 10% rust fill while controls are open) with a 5-point rust dot when an update is available.
- **Mode tabs:** "Your desk", "Library", and "Pets" as three equal-width buttons in a 3-point-padded track (primary at 4.5%, 8-point radius). The selected tab has a control-background fill, 6-point radius, and semibold text.
- **Footer:** the ⌥⌘P badge with "toggles anywhere" (or "unavailable" if registration failed), a GitHub link, and Quit.

### Your desk

- **Paper sample:** 342 × 148 points, 5-point radius, 12% hairline, no shadow. Quiet reading papers show the real overlay tile at a fixed 22% opacity; other papers use a boosted preview so their grain is recognizable. Over it: the meta-mono line, a leaf symbol, the serif paper name, and an 11-point subtitle, with 16-point padding.
- **Status row:** a 5-point dot (rust while the paper shows, secondary otherwise) and one of: "Comparing · bare screen", "Paper Mill draft on screen", "Snoozed", "Enabled · follows your app rules", or "Paused".
- **Controls:** Paper intensity (5–45%) and Matte finish (0–100%) sliders with monospaced values, then bordered small **Pause paper** / **Enable paper** and **Compare original** / **Back to paper** buttons.

### Desk setups

- Serif heading with a rust **Save current…** / **Cancel** text button that reveals a name field and **Save**.
- A three-column grid with 8-point spacing. Each card has 9-point padding and a 6-point radius, and shows a bookmark (or a checkmark when the current settings match), the intensity in mono 9, the name, and "Paper + finish" or "Paper missing".
- Selected: rust at 8% with a 55% rust hairline. Unselected: primary at 3.5% with an 8% hairline.
- At most eight setups. Saving and applying are disabled while a Paper Mill draft is previewed.

### Paper library

- **Search field:** 12-point radius, 8 × 10-point padding, control background at 90% with an 8% hairline. Focus turns the icon and a 50% hairline to the system accent. Search ignores case, accents, and repeated whitespace and matches terms in any order.
- **Header:** "Paper library" (or "Search Results" with a rust count capsule), a rust "Your desk" link, and a `…` menu with New Paper… and Import Papers… — the stable entry points for creating and adding papers.
- **Category chips** (hidden while searching): All, Light, Dark, My Papers, plus a circular + for a new paper. Capsule with 4 × 10-point padding; selected chips are rust with white text, unselected are primary at 6%. Leaving the library resets the category to All.
- **Grid:** three flexible columns with 8-point spacing, inside a row-aware fixed-height viewport capped at 356 points (360 while searching).

### Paper cards

- **Width:** 108 points with 8-point padding; three cards plus two 8-point gaps fit the content width.
- **Sample:** 92 × 52 points, 3-point radius.
- **Card:** 5-point radius. Selected: rust at 9% with a 1.5-point rust hairline and a white checkmark. Unselected: control background at 75% with a 1-point 8% hairline.
- **Text:** one-line semibold name and one-line tag (Custom, No grain, Quiet reading, Dark paper, Woven, or the start of the subtitle).
- **Context menu:** custom papers offer Edit in Paper Mill…, Export Paper…, and Delete; built-ins offer Duplicate in Paper Mill….

### Pets

- **Hero:** one card built like the desk hero (20-point radius, 7% hairline). A sage (cat) or sky (fish) stage carries the mono "DESKTOP PETS" eyebrow and a one-line rounded-bold title over a 118-point paper diorama: a torn paper floor for Miso, two folded-paper wave strips for Tide. The same retained-layer rig the desktop uses wanders there with the desktop's own motion math, animating only while the menu is visible. A panel-colored status strip below shows a green dot and "Miso is on your desk" (or "…is waiting in the menu"), with the mood and size in mono caps on the right.
- **Companion cards:** two side-by-side cards with a portrait on the pet's tonal background (Miso sitting, Tide mid-glide), framed to the drawn pose rather than the travel canvas, plus name and species. Selection = 2-point rust border plus a rust check badge — never color alone.
- **Controls card:** Mood and Size segmented pickers, a Display menu picker (Main display plus each included screen), the prominent **Bring… / Hide…** action, and a plain-language note that pets are click-through, need no permissions, and honor display/app rules. A quiet line ("Resting in place — Reduce Motion is on.") names the reason motion is paused under Reduce Motion or Low Power Mode.
- **Artwork:** jointed paper-cut puppets on a 160 × 120 canvas. Every piece is a flat cut shape over a crisp under-shadow 1.3 points below it (warm umber at 30% for Miso, deep navy at 30% for Tide), so overlaps read as stacked paper. Details (tabby stripes, scales, belly panels, bib) are clipped to their silhouettes. Miso is a ginger tabby (#EA9B57, stripes #C66E36, cream #FAECD5) in three-quarter view, jointed at hip, waist, neck, ears, and a two-part tail. The haunch is cut as its own piece, so its curve reads as the thigh in every posture. Tide is a blue fish (#3479AA over a pale #E5F3F5 belly) with pleated coral fans (#EE815E / #F9B492) for tail, dorsal, and fins. Soft shadows are drawn from fixed paths: a contact shadow under Miso and a hover shadow under Tide, as if the paper floats just above the screen.
- Pets are opt-in (off by default), independent of the paper's enabled/snooze state, and never appear on excluded displays or under blocking app rules.

### Controls and settings

- **Container:** 12-point padding, 16-point radius, primary at 3% with a 5% hairline. Its inner content card has 14-point padding and a 14-point radius on control background at 90%.
- **Tabs:** Grain, Snooze, Displays, App Rules, Settings — capsules with an icon and full label, 10 × 6-point padding. Selected tabs are filled with the system accent. The row scrolls horizontally, always overflows at 370 points, and shows a 20-point trailing fade; selecting a tab centres it so every tab is reachable by clicking.

### Notifications

- 14-point tonal banners with 12-point padding and a 36-point badge (10-point radius).
- **Update available:** accent badge and hairline, an **Update** capsule, and a dismiss button that remembers the dismissed version.
- **Installing:** a small progress indicator and "Deckle will relaunch automatically."
- **Failure:** an orange badge and hairline, the reason, and **Open release page** when a newer version is known.

### Paper Mill

- **Window:** "New Paper" or "Edit Paper"; titled, closable, miniaturizable, resizable, floating; minimum 400 × 500 points. It opens beside the MenuBarExtra window with a 12-point gap (left first, then right, otherwise clamped and the menu is hidden), up to 430 points wide and 580–720 points tall, within the owning display's visible frame.
- **Content:** 18-point padding and 14-point spacing: an 8-point-radius thumbnail with a 15% outline; **Preview on Screen** (prominent; ⌘P) that becomes a green **Stop Preview**; the name field; Comfort Starting Points; Tint; sliders for Wash, Weave, Blotch and, for fiber-engine papers, Fiber Strength, Fiber Angle, and Surface Roughness; the Appearance & Contrast card with a grade chip; the shared Intensity slider; and Delete (when editing), Cancel, and Create/Save.
- **Performance:** the thumbnail renders at 1× while a control changes and 2× once settled; the live overlay updates 180 ms after the last edit.

## Motion

- Tab, chip, and control-tab selection: 150 ms ease-in-out.
- Banner dismissal: 200 ms ease-out.
- Closing the controls panel: spring, 0.3 s response, 0.8 damping.
- Overlay show and hide: 0.4 s opacity fade.
- Mode and library size changes are not animated, so the native window resizes directly to its final size.
- With Reduce Motion on, interface animations are removed; the overlay's opacity fade remains.
- Desktop pets and their in-menu stage preview settle to a still pose under Reduce Motion and Low Power Mode, and stop entirely while pets are off, hidden, or the display sleeps. A paused pet is grounded and calm, never frozen mid-leap or mid-stride.
- Pet motion is deterministic, with no teleports:
  - Behavior comes from seeded plans, so it feels unscripted.
  - Miso's habits are sit, look back, groom, stretch, knead and nap, pounce, tail chase, and zoomies.
  - Tide's tricks are dart, loop-de-loop, nibble, doze, and barrel roll.
  - Mood changes how often each one appears.
  - Postures (sit, lie, stretch, crouch, leap, look back, groom, knead, gallop) blend over about 0.9 s.
  - Turns flip the cut-out edge-on like a card: 0.45 s for Miso, 0.6 s for Tide.
  - Miso's gait is locked to the distance walked, so paws plant instead of skating.
  - Tail and fin clocks run at a constant rate, so motion stays calm at any uptime.

## Accessibility

- Every icon-only control has a spoken name; sliders speak their value in percent or degrees; pickers carry names even when their labels are hidden.
- Selected paper cards, setups, category chips, mode tabs, and control tabs expose the selected state instead of relying on color.
- The menu bar icon's name comes from its image description ("Deckle, paper on" / "Deckle, paper off"), because MenuBarExtra ignores accessibility modifiers on its label.

## Do's and Don'ts

### Do:

- **Do** use the Apple system font and native semantic colors for controls; reserve the serif for the wordmark, paper names, and section headings.
- **Do** keep the popover at 370 points with 14-point padding and spacing.
- **Do** give every vertical `ScrollView` inside MenuBarExtra a deterministic viewport height.
- **Do** keep card dimensions explicit: 108-point paper cards, 8-point gaps, three columns.
- **Do** use monospaced digits for live percentages, countdowns, counts, and comfort metrics.
- **Do** pair semantic color with a checkmark, label, or symbol.
- **Do** make every item in a horizontally scrolling row reachable by clicking, and signal overflow.
- **Do** keep Paper Mill comfort language factual and non-medical.
- **Do** respect Reduce Motion for interface animations.

### Don't:

- **Don't** use `.frame(maxHeight:)` alone for a flexible grid inside MenuBarExtra. It may collapse while the window keeps translucent empty space.
- **Don't** stack the desk, controls, and library in one vertical state.
- **Don't** use decorative glassmorphism, gradient text, neon accents, or side-stripe borders.
- **Don't** nest cards inside cards. Use spacing, dividers, and tonal groups before another container.
- **Don't** use success, warning, or danger colors outside their semantic meaning.
- **Don't** truncate control-tab labels to make them fit. Keep the tab row scrollable and signal overflow.
- **Don't** leave blank material below the footer after a mode transition. If that occurs, the sizing contract is broken.

## Review renders

`docs/studio-desk.png`, `docs/studio-desk-dark.png`, `docs/studio-library.png`, and `docs/paper-mill.png` are rendered from the actual SwiftUI views with isolated sample preferences by `DECKLE_RENDER_DIR="$PWD/docs" swift test --filter StudioRenderTests`. They are not live menu-bar screenshots; live multi-display geometry and menu dismissal still need bundled-app verification.
