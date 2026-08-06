# RepoMind — design prompts for Stitch / Gemini

How to use: paste **BLOCK 0** first, then **one** screen prompt per generation. Never ask for more
than one screen at a time — quality drops sharply when it has to split attention.

---

## BLOCK 0 — Design system (prepend to every prompt)

```
You are designing RepoMind, a native iOS and macOS app for solo developers who manage their own
GitHub repositories. The user captures bugs and ideas by voice from their phone, and works through
them at their Mac. It is a developer tool, not a consumer to-do app.

Visual direction — this is the most important part, follow it literally:

Reference the craft level of Linear, Height, Raycast and Things 3. Specifically:
- Linear: information density, restraint, 1px hairline borders instead of drop shadows, monospace
  for identifiers, status shown as a small colored glyph rather than a loud pill.
- Raycast: dark surfaces with a soft elevation gradient, 10px corner radii, generous inner padding.
- Things 3: on iOS only — calm spacing, a single accent color, everything reachable one-handed.

Do NOT produce: Material Design, Bootstrap-looking cards, drop shadows, gray-on-gray wireframes,
rounded 16px+ bubbles, emoji, stock avatars, or generic "productivity dashboard" chrome.

Color — dark theme is the primary theme, design that first:
- Background     #0D0E12
- Surface        #16181D
- Surface hover  #1C1F26
- Hairline       rgba(255,255,255,0.08)
- Text primary   #E8EAED
- Text secondary #8B909A
- Accent         #5B6CFF  (used sparingly: one element per screen at most)
- Success        #3FB950
- Warning        #D29922
- Danger         #F85149

Typography:
- UI: SF Pro Text. Base size 13px on macOS, 15px on iOS. Titles 15/17px semibold. Never larger
  than 22px except the screen title.
- Identifiers (issue numbers, repo names, commit SHAs): SF Mono, 11-12px, text-secondary.
- Line height 1.4. Letter spacing 0.

Geometry:
- Corner radius 8px for cards, 6px for controls, 999px only for avatars.
- Border: 1px hairline. No shadows anywhere except modal overlays.
- Spacing scale: 4 / 8 / 12 / 16 / 24. Row height 36px on macOS, 52px on iOS.

Iconography: SF Symbols only, weight regular, size matched to the adjacent text.

Also produce the light theme by inverting: background #FFFFFF, surface #F6F7F9,
hairline rgba(0,0,0,0.08), text #1A1C1F / #6B7078. Same accent.
```

---

## PROMPT 1 — iOS: inside a project (board)

```
[BLOCK 0]

Screen: a single GitHub project open on iPhone (393x852).

The developer's tasks live in columns (To Do / Doing / Done), but this must feel like a native iOS
screen, not a desktop Kanban squeezed onto a phone. Design it as a horizontally paged board where
exactly ONE column fills the width at a time, and the adjacent column is hinted by 12px of the next
card peeking at the right edge.

Anatomy, top to bottom:
- Large-title navigation bar with the repo name. Below it in SF Mono 11px, the owner/name.
  Trailing: a "..." menu button.
- A segmented column indicator directly under the title: the column names as a scrollable pill row,
  the active one filled with accent at 10% opacity and accent-colored text, the rest text-secondary.
  Each shows its task count in SF Mono after the name.
- The task list for the active column: cards on Surface, 8px radius, hairline border, 12px inner
  padding, 8px gap between cards. Each card shows:
    - the task text, 15px, up to 2 lines
    - a metadata row 8px below: issue number in SF Mono (#142), a 6px status dot, and a small
      paperclip glyph if it has a screenshot
    - one card in the mock has a 56px-tall screenshot thumbnail on its right side
- A floating circular microphone button, 56px, accent fill, bottom-right, 16px from the edges,
  with a soft accent glow at 20% opacity.

Show 4 cards in To Do. Include an empty-state treatment for a column with no tasks: a centered
SF Symbol at 24px in text-secondary and one line of text, nothing more.

Show the dark theme first, then the same screen in light theme.
```

---

## PROMPT 2 — iOS: same screen, list-first alternative

Generate this one too and compare them side by side before deciding.

```
[BLOCK 0]

Screen: the same iPhone project screen, but as an alternative concept — no columns at all.

One continuous grouped list. Section headers are the column names in 11px uppercase
text-secondary with the count in SF Mono on the trailing edge. Rows are 52px, separated by
hairlines that inset 16px from the left, no cards.

Each row: a leading 20px circular checkbox-style status control whose ring color matches the
column; the task text at 15px truncated to one line; trailing metadata in SF Mono 11px.
Swiping a row left reveals "Move" and "Done" actions — show one row mid-swipe.

The point of this concept is that moving a task between columns happens through the row's status
control and swipe actions rather than by dragging across a board. Make that legible in the design.

Same floating microphone button as the board concept.

Dark theme first, then light.
```

---

## PROMPT 3 — macOS: project window

```
[BLOCK 0]

Screen: RepoMind on macOS, 1280x800, a real Mac app window with traffic lights.

Three-pane layout:
- Sidebar, 220px, on a slightly darker surface than the content area. Sections in 11px uppercase
  text-secondary: "Inbox", then "Repositories" listing 5 repos, each row 28px with a 16px repo
  avatar, the name at 13px, and an unread count badge in SF Mono on the trailing edge for two of
  them. The selected row has a Surface-hover fill and a 2px accent bar on its leading edge.
- Center: the board. Three columns side by side, each 320px wide, separated by hairlines, NOT by
  gaps or background color changes. Column header is a 28px row: the name at 13px semibold, the
  count in SF Mono, and a "+" glyph that only appears on hover. Cards are 8px radius, hairline,
  12px padding, 6px apart. Show 4 / 2 / 3 cards.
- Right inspector, 300px, showing the selected task: its full text, the linked GitHub issue with
  its state, a screenshot thumbnail, and a comment thread with two entries.

The toolbar holds a search field (240px, 6px radius, Surface fill) and a "Sync" button showing a
relative timestamp underneath in 11px text-secondary.

This must read as a dense professional Mac tool. Every row should feel tight — if it looks
comfortable, it is too loose. Dark theme first, then light.
```

---

## PROMPT 4 — iOS: voice capture

```
[BLOCK 0]

Screen: iPhone (393x852), the voice capture sheet, mid-recording.

Presented as a sheet over the project screen — show the parent screen dimmed behind it at the top.
The sheet has a 16px top corner radius and fills 70% of the height.

Contents:
- A recording indicator at the top: a 6px pulsing dot in danger red and "Listening" at 13px.
- The live transcription as the hero: the developer's words in 22px regular text, left-aligned,
  filling the upper third, with the most recent words at full opacity and earlier ones at 60%.
  Use realistic content: "the login screen jumps when the keyboard opens on iPhone".
- A live waveform below it: 24 vertical bars, 3px wide, 2px apart, accent colored, heights varying
  to suggest speech, centered on a baseline.
- A row showing which repository and column the task will land in, as two small pills with a
  chevron, tappable.
- Two buttons at the bottom: a 48px circular cancel (Surface fill, x glyph) and a 64px circular
  confirm (accent fill, checkmark). The confirm is visually dominant.

Dark theme only — this screen is used at night and in bed.
```

---

## PROMPT 5 — iOS: home / repository list

```
[BLOCK 0]

Screen: iPhone (393x852), the app's home — the list of repositories.

- Large title "Repositories", with a search field below it that scrolls away.
- At the very top, above the repos, a compact "Today" summary card: Surface fill, hairline, 12px
  padding, containing up to three single-line entries such as "3 unread reports", "2 tasks not
  published" — each with a 14px SF Symbol on the leading edge and a chevron trailing. If there is
  nothing to show, this card does not exist at all — show that version too.
- Repository rows, 64px: a 32px rounded-square repo avatar, the repo name at 15px semibold, the
  owner in SF Mono 11px underneath, and on the trailing edge a task count in SF Mono plus a small
  accent dot when the repo has unread feedback.
- One row shows a private-repo lock glyph next to its name.

Dark theme first, then light.
```

---

## Iterating in Stitch

Stitch throws away your intent if you re-describe the whole screen. Change one thing at a time:

- "Keep the layout exactly as it is. Only change X."
- "Too much padding. Reduce every vertical gap by a third and make row height 44px."
- "Remove all drop shadows and replace them with 1px hairline borders at rgba(255,255,255,0.08)."
- "The accent color is used in six places. Use it in one — the primary action only."
- "Make the type smaller and denser, like Linear. Nothing above 15px except the screen title."

If a result looks generic it is almost always one of three things: the corner radii are too large,
there are shadows, or the type is too big. Fix those three first.
