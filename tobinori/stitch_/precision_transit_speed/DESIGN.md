---
name: Precision Transit Speed
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#424656'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#737687'
  outline-variant: '#c3c6d8'
  surface-tint: '#0052dd'
  primary: '#004ccd'
  on-primary: '#ffffff'
  primary-container: '#0f62fe'
  on-primary-container: '#f3f3ff'
  inverse-primary: '#b4c5ff'
  secondary: '#a04100'
  on-secondary: '#ffffff'
  secondary-container: '#fe6b00'
  on-secondary-container: '#572000'
  tertiary: '#006076'
  on-tertiary: '#ffffff'
  tertiary-container: '#007a95'
  on-tertiary-container: '#e6f7ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dbe1ff'
  primary-fixed-dim: '#b4c5ff'
  on-primary-fixed: '#00174c'
  on-primary-fixed-variant: '#003da9'
  secondary-fixed: '#ffdbcc'
  secondary-fixed-dim: '#ffb693'
  on-secondary-fixed: '#351000'
  on-secondary-fixed-variant: '#7a3000'
  tertiary-fixed: '#b6ebff'
  tertiary-fixed-dim: '#47d6ff'
  on-tertiary-fixed: '#001f28'
  on-tertiary-fixed-variant: '#004e60'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-time-lg:
    fontFamily: JetBrains Mono
    fontSize: 48px
    fontWeight: '800'
    lineHeight: 52px
    letterSpacing: -0.04em
  display-time-mobile:
    fontFamily: JetBrains Mono
    fontSize: 36px
    fontWeight: '800'
    lineHeight: 40px
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Noto Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Noto Sans
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Noto Sans
    fontSize: 18px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: 0em
  body-lg:
    fontFamily: Noto Sans
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
    letterSpacing: 0em
  body-md:
    fontFamily: Noto Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Noto Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-code-lg:
    fontFamily: JetBrains Mono
    fontSize: 16px
    fontWeight: '700'
    lineHeight: 20px
    letterSpacing: -0.02em
  label-code-md:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: -0.01em
  label-code-sm:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  space-2xs: 0.25rem
  space-xs: 0.5rem
  space-sm: 0.75rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
  space-2xl: 3rem
  layout-margin-mobile: 1rem
  layout-margin-tablet: 1.5rem
  layout-margin-desktop: 2rem
  layout-gutter: 1rem
---

## Brand & Style

This design system embodies the punctuality, mechanical precision, and streamlined motion of Japan's world-class transit grid. The emotional response is pure clarity and instantaneous relief: eliminating decision fatigue by surfacing exclusively the single optimal route in milliseconds.

The visual direction marries **High-Contrast Utilitarianism** with **Modern Japanese Signage Aesthetics**:
- **Zero Ambiguity:** Information density is controlled strictly by visual hierarchy. Critical data points (departure countdown, platform number, line transfer points) are rendered with stark, unmistakable priority.
- **Dynamic Speed:** Crisp edges, electric accents, and micro-animations reminiscent of express train line indicators convey unmatched technical performance.
- **Architectural Clarity:** Layouts draw inspiration from modern Japanese station typography and wayfinding boards—structured, uncluttered, and effortlessly legible under high-glare transit conditions.

## Colors

The palette is engineered for rapid visual processing in bright ambient environments like platforms and concourses:

- **Express Blue (`#0F62FE`):** Anchors the interface. Used for dominant interactive triggers, transit paths, and primary active states.
- **Rapid Amber / Orange (`#FF6B00`):** Denotes acute urgency, departure countdowns, direct Shinkansen/Limited Express identifiers, and transfer alerts.
- **Electric Cyan (`#00D2FF`):** Operates as a tertiary pulse indicator—live tracking pings, current location markers, and progress glow states.
- **Deep Navy Neutral (`#0F172A`):** Pure textual contrast without the harshness of pure black; used for primary typography, solid navigation tabs, and dark modal surfaces.
- **Canvas System:** Base canvas rests on `#F8FAFC`, elevated surface elements rest on `#FFFFFF`, and structural sub-borders utilize `#E2E8F0`.

## Typography

The typographic hierarchy prioritizes instantaneous scanning:

- **Timetable Precision:** Departure/arrival times, countdown metrics, platform numbers, and durations exclusively use the monospaced technical font (`JetBrains Mono`). This keeps numerical data aligned without shifting layouts during real-time tick updates.
- **Wayfinding Readability:** Primary station titles, transfer line directions, and action buttons use `Noto Sans`, configured with robust weights (`500` to `700`) to replicate Japanese municipal rail signboards.
- **Tabular Figures:** Always render timestamps with tabular numbers enabled to eliminate horizontal jitter during live transit tracking.

## Layout & Spacing

The layout is built around a single-column, single-purpose canvas that delivers instant answers:

- **Single Optimal Route Architecture:** Unlike traditional search portals with paginated options, the screen is engineered to host one hero route module accompanied by micro-breakdowns (timeline, map viewport, vehicle configuration).
- **Grid Structure:**
  - **Mobile (<768px):** Fluid single column with `1rem` edge safe-zones. Interactive inputs and quick-toggle destinations pin to the bottom thumb-zone.
  - **Desktop / Tablet (>=768px):** Centered high-efficiency viewport capped at a maximum width of `560px` for telephone navigation, or a split-pane layout (`440px` route deck + flexible map viewport) for wide workspaces.
- **Rhythm:** An 8px spatial grid dominates component dimensions. Gap spacing between timeline station stops remains strictly pinned to `1.5rem` (`space-lg`) to allow continuous vertical transit lines.

## Elevation & Depth

This system avoids heavy skeuomorphic shadows, relying instead on **tactile tonal layering and high-contrast structural borders**:

- **Ground Level (Base Canvas):** `#F8FAFC` flat surface.
- **Surface Level 1 (Cards & Inputs):** `#FFFFFF` background with a crisp `1px` border of `#E2E8F0` and a ultra-subtle ambient drop shadow: `0 2px 8px -2px rgba(15, 23, 42, 0.05)`.
- **Surface Level 2 (Floating Action Search Bar & Hero Route Cards):** High-prominence cards use an intensified perimeter rim: `1px solid rgba(15, 98, 254, 0.15)` paired with `0 12px 24px -6px rgba(15, 23, 42, 0.08)`.
- **Level 3 (Overlays & Bottom Sheets):** Deep Navy tint backdrop blur (`rgba(15, 23, 42, 0.4)` with `backdrop-filter: blur(8px)`), elevating modal dialogs and live route guidance notifications.

## Shapes

The design system embraces a **Functional Compactness** shape language (`roundedness: 2` / base `8px` corner radius):

- **Interactive Primary Elements:** Buttons, search inputs, and primary route cards use an `8px` (`0.5rem`) to `12px` corner radius. This conveys high-tech structure rather than casual playfulness.
- **Station Badges & Line Chips:** Station codes, transit line identifiers, and rapid departure labels are encapsulated in compact capsules (`9999px` full-pill) or geometric squircles (`4px` radius) to replicate physical platform signage.

## Components

### 1. One-Tap Instant Search Bar
- **Form:** Sticky bottom/top floating bar with integrated geolocator icon (flashing Electric Cyan dot).
- **Interaction:** Tap-to-swap origin/destination, pre-filled with "現在地 (Current Location)". Immediate reactive autocomplete with zero transition delays.

### 2. The Hero Route Card (1件完結型ルートカード)
- **Structure:**
  - **Header Bar:** Monospaced departure time, arrival time, and total time elapsed (`所要時間`) highlighted in deep neutral against a bright amber indicator badge for the quickest connection (`最速`).
  - **Vertical Transit Thread:** A continuous 4px vertical timeline linking stations. Line colors match official train line branding (e.g., Yamanote green, Marunouchi red) or fallback to Express Blue.
  - **Station Nodes:** Open rings for transfer points; solid filled points for origin/terminal.
  - **Transfer Alerts:** Inline warning pills showing walk distance (`徒歩2分`), target platform (`3番線発`), and optimal car position (`乗車位置: 4号車・8号車`).

### 3. Transit Badges & Chips
- **Line Badges:** High-contrast background with line symbol and name, framed with 2px borders (e.g., `JR 山手線`, `東京メトロ 丸ノ内線`).
- **Urgency Chips:** Amber countdown chips showing dynamic remaining minutes (`あと 3分で発車`).

### 4. Interactive Minimal Map Card
- **Styling:** Desaturated map layer (`#F1F5F9`) with bright primary blue paths and glowing cyan position pins.
- **Height & Behavior:** Collapsed to a 140px overview banner by default, expandable to full view via a single gesture.

### 5. Buttons & Controls
- **Primary CTA:** Deep Express Blue (`#0F62FE`), white bold typography, active press state shifts -1px on the Y-axis with an intensified inset ring.
- **Secondary Actions:** White fill, 1px `#CBD5E1` border, `#0F172A` label text.