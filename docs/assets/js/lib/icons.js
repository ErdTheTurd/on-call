/**
 * Line icons standing in for the SF Symbols the iOS app uses.
 *
 * Drawn on a 24×24 grid with `currentColor` so they inherit text colour and
 * size from their container, the way SF Symbols track their text style.
 * Emoji were used here previously; they render differently on every platform
 * and never matched the app.
 */

const PATHS = {
  // Tab bar — doctor
  home: '<path d="M3 10.2 12 3.5l9 6.7V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  shifts: '<path d="M4 9a8 8 0 0 1 13.3-3.3L20 8"/><path d="M20 4v4h-4"/><path d="M20 15a8 8 0 0 1-13.3 3.3L4 16"/><path d="M4 20v-4h4"/>',
  credentials: '<path d="m12 3 2.2 1.6 2.7-.2 1 2.5 2.3 1.4-.7 2.6.7 2.6-2.3 1.4-1 2.5-2.7-.2L12 19l-2.2-1.6-2.7.2-1-2.5L3.8 13.7l.7-2.6-.7-2.6 2.3-1.4 1-2.5 2.7.2z"/><path d="m9 11.5 2 2 4-4"/>',

  // Tab bar — hospital
  dashboard: '<path d="M3 10.2 12 3.5l9 6.7V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/><path d="M12 14v3l2 1"/>',
  doctors: '<circle cx="9" cy="9" r="3.2"/><path d="M3.5 20a5.5 5.5 0 0 1 11 0"/><path d="M16 6.3a3.2 3.2 0 0 1 0 5.9"/><path d="M17.6 14.5A5.5 5.5 0 0 1 20.5 20"/>',

  // Chrome
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  chevronLeft: '<path d="m15 5-7 7 7 7"/>',
  chevronUp: '<path d="m5 15 7-7 7 7"/>',
  chevronDown: '<path d="m5 9 7 7 7-7"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',

  // Status and semantics
  check: '<path d="m4 12.5 5 5L20 6.5"/>',
  checkCircle: '<circle cx="12" cy="12" r="9"/><path d="m8 12.2 2.7 2.7L16 9.6"/>',
  xmarkCircle: '<circle cx="12" cy="12" r="9"/><path d="m9 9 6 6M15 9l-6 6"/>',
  warning: '<path d="M12 4.5 21 19.5H3z"/><path d="M12 10v4M12 17h.01"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.2 2"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8.5 10.5V7.8a3.5 3.5 0 0 1 7 0v2.7"/>',

  // Urgency (mirrors the iOS tiers)
  bolt: '<path d="M13.5 3 5.5 13.5H11l-.5 7.5 8-10.5H13z"/>',
  flame: '<path d="M12 3c3.2 4 5 6.4 5 9a5 5 0 0 1-10 0c0-1.5.6-2.8 1.8-4.2.5 1.2 1.2 2 2 2.3C11.3 8 11.6 5.7 12 3Z"/>',
  crossCase: '<rect x="3" y="7.5" width="18" height="12.5" rx="2.5"/><path d="M9 7.5V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v1.5"/><path d="M12 11.2v5M9.5 13.7h5"/>',
  moon: '<path d="M20 14.2A8.2 8.2 0 0 1 9.8 4 8.4 8.4 0 1 0 20 14.2Z"/>',

  // Content
  sparkles: '<path d="M12 4c.9 3.4 2.3 4.8 5.6 5.7-3.3.9-4.7 2.3-5.6 5.7-.9-3.4-2.3-4.8-5.6-5.7C9.7 8.8 11.1 7.4 12 4Z"/><path d="M18 15.5c.4 1.5 1 2.1 2.5 2.5-1.5.4-2.1 1-2.5 2.5-.4-1.5-1-2.1-2.5-2.5 1.5-.4 2.1-1 2.5-2.5Z"/>',
  stethoscope: '<path d="M6 3v5a4 4 0 0 0 8 0V3"/><path d="M10 12v2.5a5 5 0 0 0 5 5 3.5 3.5 0 0 0 3.5-3.5V14"/><circle cx="18.5" cy="12.2" r="2"/>',
  hospital: '<path d="M4 21V6.5L12 3l8 3.5V21"/><path d="M12 9v5M9.5 11.5h5"/><path d="M9 21v-4h6v4"/>',
  dollar: '<path d="M12 3.5v17"/><path d="M16 7.5c-.8-1.2-2.2-2-4-2-2.2 0-3.8 1.2-3.8 3s1.5 2.6 3.8 3.1c2.5.6 4 1.4 4 3.3 0 1.9-1.7 3.1-4 3.1-1.9 0-3.4-.8-4.2-2.1"/>',
  envelope: '<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="m4 7.5 8 5.5 8-5.5"/>',
  ticket: '<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h13A1.5 1.5 0 0 1 20 8.5v2a2 2 0 0 0 0 3.9v2a1.5 1.5 0 0 1-1.5 1.6h-13A1.5 1.5 0 0 1 4 16.4v-2a2 2 0 0 0 0-3.9z"/><path d="M14 7v10"/>',
  person: '<circle cx="12" cy="8" r="3.4"/><path d="M5.5 20a6.5 6.5 0 0 1 13 0"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  megaphone: '<path d="M4 10v4a1.5 1.5 0 0 0 1.5 1.5H8l7 4.5V5.5L8 10H5.5A1.5 1.5 0 0 0 4 10Z"/><path d="M18 9.5a4 4 0 0 1 0 5"/>',
  refresh: '<path d="M4 9a8 8 0 0 1 13.3-3.3L20 8"/><path d="M20 4v4h-4"/><path d="M20 15a8 8 0 0 1-13.3 3.3L4 16"/><path d="M4 20v-4h4"/>',
  slider: '<path d="M4 8h10M18 8h2M4 16h4M12 16h8"/><circle cx="16" cy="8" r="2"/><circle cx="10" cy="16" r="2"/>',
  chart: '<path d="M4 20V10M10 20V5M16 20v-7M22 20H2"/>',
  card: '<rect x="3" y="6" width="18" height="12" rx="2.5"/><path d="M3 10h18"/>',
  signOut: '<path d="M14 4h4.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H14"/><path d="M10 8.5 6 12l4 3.5M6 12h9"/>'
};

PATHS.wand = PATHS.sparkles;

const FILLED = new Set(["home", "dashboard", "bolt", "flame", "sparkles", "moon", "person", "megaphone"]);

/**
 * Returns an inline SVG string. Unknown names render nothing rather than a
 * placeholder glyph, so a typo can never ship a stray dot into the UI.
 */
export function icon(name, { size = 20, className = "" } = {}) {
  const path = PATHS[name];
  if (!path) return "";

  const filled = FILLED.has(name);
  return `<svg class="ic ${className}" viewBox="0 0 24 24" width="${size}" height="${size}" aria-hidden="true"
    fill="${filled ? "currentColor" : "none"}"
    stroke="${filled ? "none" : "currentColor"}"
    stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
}

export function hasIcon(name) {
  return Boolean(PATHS[name]);
}
