export const BRAND = {
  bg: "#070B17",
  accent: "#4F8EF7",
  accentAlt: "#8B5CF6",
  danger: "#F87171",
  success: "#34D399",
  warning: "#FBBF24"
};

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
