# Deckle 2.0.0 release plan

> **Status:** prepared. This file is the record for Deckle 2.0.0 (build 21); follow the release steps in `AGENTS.md` for future releases.

Target: Deckle 2.0.0, build 21. Deckle 1.9.0, build 20 was the latest
published release when this candidate was prepared; the new build number exceeds
every published build.

## Why a major version

Deckle gains a second product surface: opt-in desktop pets that animate in their
own window. The paper overlay is unchanged and stays fully static, but a
companion that moves on screen is a visible shift in what the app does, so the
release is 2.0.0.

## Scope

- **Paper-cut desktop pets (#57).** Miso, a jointed ginger tabby, and Tide, a
  pleated paper fish, live in one small click-through window with a Pets tab.
  Mood, size, and display are configurable. Behavior comes from seeded plans:
  - Miso sits, looks back, grooms, stretches, kneads and naps, pounces, chases
    its tail, and gets the zoomies.
  - Tide darts, loops the loop, nibbles, dozes, and barrel-rolls.
- **Echo companion and studio-wide visual pass (#55).**
- **Renderer memory footprint cut (#56).**
- **Hardened updater, rendering, settings, and accessibility (#53)**, and docs
  that match the code exactly (#54).

## Release checks

- Pets are opt-in (off by default) and independent of the paper's enabled,
  snooze, comparison, and Paper Mill preview states.
- Pets never appear on excluded displays or under blocking app rules, and they
  honor Hide from screen capture.
- Pet motion stops while pets are off or hidden, the display sleeps, or the
  session is inactive. Under Reduce Motion or Low Power Mode the pet settles
  into a grounded still pose.
- The pet window stays within the display's visible frame at every size, and
  no pose draws outside its canvas (`PetArtworkTests`).
- Posture arithmetic uses short typed terms so the Xcode 15.4 release compiler
  does not time out type-checking it.

## Verification and release sequence

1. Merge the feature (#57) and the release PR into `main`; the default branch
   requires one approving review.
2. Run `plutil -lint Support/Info.plist`, `swift test`, and
   `make build UNIVERSAL=1` against the final candidate.
3. Create the annotated tag `v2.0.0` ("Deckle 2.0.0") on the release merge
   commit and push it. This triggers publication.
4. Verify the workflow validates the plist, tag/version agreement, and full test
   suite on Xcode 15.4, then builds the universal DMG, signs, notarizes,
   staples, creates its checksum, and publishes both assets. Never move an
   already published tag.

## Validation record

- `plutil -lint Support/Info.plist` and `git diff --check`: passed.
- `swift test`: 129 tests passed, 0 failures (6 opt-in rendering tests skipped).
- `make build UNIVERSAL=1`: passed.
- `make app`: the bundled app ran with pets enabled. The pet window measured
  120 × 90 points at Small and sat at the screen-saver level. With Hide from
  screen capture on, it was absent from captures as designed. Window-server
  composites confirmed the contact and hover shadows.
