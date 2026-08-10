export const BRAND = {
  name: "MD Shift",
  tagline: "Smarter shift scheduling",
  bg: "#070B17",
  accent: "#4F8EF7",
  accentAlt: "#8B5CF6",
  danger: "#F87171",
  success: "#34D399",
  warning: "#FBBF24"
};

/** Heart-rate mark used on the marketing site and auth — not the favicon. */
export function brandMark({ size = 28 } = {}) {
  return `
    <svg viewBox="0 0 28 28" width="${size}" height="${size}" fill="none" aria-hidden="true">
      <rect width="28" height="28" rx="8" fill="var(--blue, #2563eb)"/>
      <path d="M5.5 14.5h3.2l2.1-4.6 3.4 9.2 2.2-4.6h6.1"
            stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;
}

export function brandLockup({ size = 28 } = {}) {
  return `
    <span class="logo">
      ${brandMark({ size })}
      <span>${BRAND.name}</span>
    </span>`;
}

export const SPECIALTIES = [
  "Internal Medicine",
  "Orthopedics",
  "Ob/Gyn",
  "ENT",
  "Emergency Medicine",
  "Anesthesiology",
  "Radiology",
  "Surgery",
  "Pediatrics",
  "Psychiatry",
  "Cardiology",
  "Neurology",
  "Hospitalist"
];

export const CREDENTIALS = ["MD", "DO", "NP", "PA"];

export const VERIFICATION = {
  unverified: { label: "Not Verified", icon: "?" },
  pending: { label: "Pending Review", icon: "⏱" },
  verified: { label: "Verified", icon: "✓" },
  flagged: { label: "Needs Review", icon: "!" },
  waitlisted: { label: "Waitlisted", icon: "❋" },
  rejected: { label: "Rejected", icon: "✕" }
};

export function uuid() {
  return crypto.randomUUID();
}

export function startOfDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function sameDay(a, b) {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

export function formatShiftDate(date, perDay = true) {
  const d = new Date(date);
  if (perDay) {
    return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  }
  return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

export function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
