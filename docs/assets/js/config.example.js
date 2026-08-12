// Copy this file to config.js and paste your real Supabase project URL and anon key.
// Use the same values as Config/Secrets.xcconfig in the iOS app (SUPABASE_URL / SUPABASE_ANON_KEY).
window.ON_CALL_CONFIG = {
  supabaseUrl: "https://your-project.supabase.co",
  supabaseAnonKey: "your-anon-key",
  websiteBaseUrl: "https://mdshift.net",
  appStoreUrl: "",
  appScheme: "oncallwizard",
  appBundleId: "com.eporthospine.mdshift",
  // MD Shift+ ($9.99/mo) — Stripe Payment Link OR edge function create-plus-checkout
  stripePlusPaymentLink: "",
  // Real ads — Google AdSense (web + iOS WKWebView banner page)
  adsenseClient: "",       // e.g. ca-pub-xxxxxxxxxxxxxxxx
  adsenseBannerSlot: ""    // Ad unit slot id
};
