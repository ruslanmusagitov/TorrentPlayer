---
name: Kinetic Torrent
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f3'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1b1b1b'
  on-surface-variant: '#5a4136'
  inverse-surface: '#303030'
  inverse-on-surface: '#f1f1f1'
  outline: '#8e7164'
  outline-variant: '#e2bfb0'
  surface-tint: '#a04100'
  primary: '#a04100'
  on-primary: '#ffffff'
  primary-container: '#ff6b00'
  on-primary-container: '#572000'
  inverse-primary: '#ffb693'
  secondary: '#0001c0'
  on-secondary: '#ffffff'
  secondary-container: '#080cff'
  on-secondary-container: '#b6baff'
  tertiary: '#506600'
  on-tertiary: '#ffffff'
  tertiary-container: '#83a500'
  on-tertiary-container: '#293600'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdbcc'
  primary-fixed-dim: '#ffb693'
  on-primary-fixed: '#351000'
  on-primary-fixed-variant: '#7a3000'
  secondary-fixed: '#e0e0ff'
  secondary-fixed-dim: '#bec2ff'
  on-secondary-fixed: '#00006e'
  on-secondary-fixed-variant: '#0000ef'
  tertiary-fixed: '#c3f400'
  tertiary-fixed-dim: '#abd600'
  on-tertiary-fixed: '#161e00'
  on-tertiary-fixed-variant: '#3c4d00'
  background: '#f9f9f9'
  on-background: '#1b1b1b'
  surface-variant: '#e2e2e2'
typography:
  display:
    fontFamily: Hanken Grotesk
    fontSize: 48px
    fontWeight: '900'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Hanken Grotesk
    fontSize: 32px
    fontWeight: '800'
    lineHeight: '1.2'
  headline-lg-mobile:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '800'
    lineHeight: '1.2'
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '500'
    lineHeight: '1.5'
  technical-md:
    fontFamily: Space Mono
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.4'
  technical-sm:
    fontFamily: Space Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.4'
  label-caps:
    fontFamily: Space Mono
    fontSize: 11px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: 0.1em
spacing:
  base: 4px
  xs: 8px
  sm: 16px
  md: 24px
  lg: 40px
  border-thick: 3px
  shadow-offset: 4px
---

## Brand & Style
This design system leverages **Neo-Brutalism** to mirror the raw, unthrottled nature of peer-to-peer file sharing. The aesthetic prioritizes technical transparency and high-performance utility over decorative softness. 

The target audience consists of power users, developers, and media archivists who value speed and clarity. The UI should evoke a sense of structural honesty—exposing the mechanics of the stream through heavy strokes, stark contrasts, and a "no-nonsense" layout. Movement is sharp and immediate, avoiding ease-in-out transitions in favor of linear, mechanical responses.

## Colors
The palette is built on high-energy "Digital Signals." The background is a stark, slightly industrial light grey (#F2F2F2) to reduce eye strain compared to pure white while maintaining high contrast.

- **Primary (Safety Orange):** Reserved for critical actions: "Download," "Stream Now," and active state indicators.
- **Secondary (Electric Blue):** Used for technical metadata, magnet links, and secondary navigation elements.
- **Tertiary (Lime Green):** Specifically for "Health" indicators (seeders, successful connections, completed downloads).
- **Neutral (Black):** Used for all structural borders, hard shadows, and primary text.

## Typography
The system uses a dual-font approach. **Hanken Grotesk** provides a heavy, authoritative presence for headings and primary UI labels, utilizing tight tracking and bold weights to anchor the layout.

**Space Mono** is utilized for all "Data Layers." This includes file paths, hash strings, peer counts, and transfer speeds. This distinction ensures that the user can immediately differentiate between "Interface" and "Information." All labels for technical data should be set in Uppercase `label-caps`.

## Layout & Spacing
The layout follows a rigid 8px grid system. Unlike fluid modern designs, this system emphasizes "Container-First" logic. 

- **Desktop (macOS):** A 12-column grid with 0px gutters; components are separated by shared 3px borders to create a monolithic, "table-like" structure.
- **Tablet/Mobile:** A single-column stack with heavy 24px outer margins. 
- **Dividers:** Use 3px solid black lines for primary section breaks. Use 1px solid black lines for internal list item separation.
- **Padding:** Generous internal padding (24px) within containers to offset the visual weight of the thick borders.

## Elevation & Depth
Depth is strictly two-dimensional, achieved through **Hard Shadows** (Neo-Brutalism). 
- Do not use Gaussian blurs or soft ambient shadows.
- Elevation is represented by a solid black offset. 
- **Level 1 (Default):** 4px offset to the bottom-right (4px 4px 0px 0px #000).
- **Level 2 (Hover/Active):** 8px offset to the bottom-right.
- **Level 0 (Pressed):** 0px offset (element moves "down" into the page).
- Background layers are flat; use a "safety orange" or "electric blue" solid fill for active container backgrounds rather than shadows to show focus.

## Shapes
The shape language is strictly orthogonal. 
- **Corner Radius:** 0px for all main containers, buttons, and input fields.
- **Exceptions:** Very small 2px radius may be applied to nested "status tags" or "pills" only if they contain technical data, to distinguish them from actionable buttons.
- **Borders:** Every interactive element must have a minimum 2px solid black border. Primary containers use 3px.

## Components

### Buttons
- **Primary:** Safety Orange fill, 3px black border, 4px hard black shadow. Text in Hanken Grotesk Bold.
- **Secondary:** White fill, 3px black border, 4px hard black shadow.
- **States:** On click/tap, the element translates +4px on X and Y axes, and the shadow disappears to simulate a physical "press."

### Technical Cards
- Used for torrent entries. Square corners, 2px border.
- Header of the card uses a solid Electric Blue fill with white text.
- Metadata (Size, Seeds, Peers) displayed in a grid using Space Mono.

### Inputs
- Pure white background, 3px border.
- Placeholder text in Space Mono (50% opacity).
- Active focus state: The border color changes to Safety Orange or the background shifts to a very pale yellow.

### Progress Bars
- High-contrast containers (3px border).
- The fill should be a solid, non-gradient Lime Green (#CCFF00).
- For stalled torrents, use a diagonal "hazard stripe" pattern (Black and Grey).

### Status Chips
- Small rectangular blocks with 1px borders. 
- Use the technical-sm typography.
- Use Tertiary (Lime Green) for "Seeding" and Primary (Orange) for "Downloading."