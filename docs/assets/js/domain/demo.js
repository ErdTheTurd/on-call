import { uuid, startOfDay } from "../brand.js";
import {
  KEYS, appStore, beginSession, DEMO_HOSPITAL_ID, seedMockDoctors
} from "../store.js";

const DEMO_FLAG = "oncall_demo_mode";

const DOCTOR_USER_ID = "00000000-0000-4000-9000-000000000001";
const HOSPITAL_USER_ID = "00000000-0000-4000-9000-000000000002";

const HOSPITALS = [
  { id: DEMO_HOSPITAL_ID, name: "Riverside General" },
  { id: "00000000-0000-4000-8000-000000000002", name: "St. Anne's Medical Center" },
  { id: "00000000-0000-4000-8000-000000000003", name: "Lakeshore Regional" }
];

/** Base day rates that read as plausible to anyone who has staffed a rota. */
const BASE_RATES = {
  "Emergency Medicine": 1450,
  "Internal Medicine": 1150,
  Cardiology: 1600,
  Anesthesiology: 1750,
  Hospitalist: 1200,
  Surgery: 1900
};

export function isDemoSession() {
  return localStorage.getItem(DEMO_FLAG) === "1";
}

export function clearDemoFlag() {
  localStorage.removeItem(DEMO_FLAG);
}

/** Wipes any earlier demo so every walkthrough starts from the same story. */
function resetLocalData() {
  for (const key of Object.values(KEYS)) {
    if (key === KEYS.accounts) continue;
    localStorage.removeItem(key);
  }
}

function dayAt(offset, hour = 7) {
  const d = startOfDay(new Date());
  d.setDate(d.getDate() + offset);
  d.setHours(hour, 0, 0, 0);
  return d;
}

function makeShift(hospital, specialty, date, rate) {
  return {
    id: uuid(),
    hospitalID: hospital.id,
    hospital: hospital.name,
    specialty,
    start: date.toISOString(),
    durationHours: 24,
    rateFloor: rate,
    rateUnit: "per day",
    escalationMode: { type: "automatic" },
    usesAlgorithmPricing: true
  };
}

function demoDoctorProfile() {
  return {
    id: DOCTOR_USER_ID,
    userID: DOCTOR_USER_ID,
    firstName: "Maya",
    lastName: "Ellison",
    credential: "MD",
    npi: "1487290365",
    deaNumber: "",
    licenseNumber: "A48219",
    licenseState: "CA",
    specialties: ["Emergency Medicine", "Internal Medicine"],
    email: "m.ellison@riversidegeneral.org",
    verificationStatus: "verified",
    verificationFlags: [],
    documents: []
  };
}

/** A doctor mid-career: a few shifts booked and one trade waiting on them. */
function seedDoctor() {
  const profile = demoDoctorProfile();
  appStore.saveDoctorProfile(profile);

  // Each hospital needs 30+ upcoming days on the board, otherwise the app's own
  // filler kicks in and buries these named hospitals under generic demo shifts.
  const rotation = [
    "Emergency Medicine", "Internal Medicine", "Cardiology",
    "Emergency Medicine", "Internal Medicine", "Hospitalist"
  ];
  const shifts = [];
  for (let offset = 1; offset <= 32; offset++) {
    const date = dayAt(offset);
    const weekend = [0, 6].includes(date.getDay());
    HOSPITALS.forEach((hospital, index) => {
      const specialty = rotation[(offset + index) % rotation.length];
      const base = BASE_RATES[specialty] || 1200;
      shifts.push(makeShift(hospital, specialty, date, weekend ? base + 250 : base));
    });
  }

  const booked = [
    { specialty: "Emergency Medicine", offset: 2, hospital: HOSPITALS[0] },
    { specialty: "Internal Medicine", offset: 6, hospital: HOSPITALS[1] },
    { specialty: "Emergency Medicine", offset: 11, hospital: HOSPITALS[0] }
  ].map(({ specialty, offset, hospital }) =>
    makeShift(hospital, specialty, dayAt(offset), BASE_RATES[specialty])
  );

  appStore.saveShifts([...shifts, ...booked]);

  appStore.saveAssignments(booked.map((shift) => ({
    id: uuid(),
    shiftID: shift.id,
    shift,
    doctorID: profile.id,
    doctorName: `${profile.firstName} ${profile.lastName}`,
    status: "scheduled",
    assignedAt: new Date(Date.now() - 3 * 86400000).toISOString()
  })));

  seedMockDoctors();

  // One colleague wants to swap, so the trade flow has something to open.
  const tradedShift = booked[2];
  appStore.saveTrades({
    incoming: [{
      id: uuid(),
      shiftID: tradedShift.shiftID || tradedShift.id,
      fromDoctorID: appStore.roster[2]?.id || uuid(),
      fromDoctorName: "Dr. Maria Santos",
      toDoctorID: profile.id,
      toDoctorName: `${profile.firstName} ${profile.lastName}`,
      specialty: tradedShift.specialty,
      offeredDate: dayAt(9).toISOString(),
      requestedDate: tradedShift.start,
      compensationAmount: 250,
      state: "pending",
      createdAt: new Date(Date.now() - 5 * 3600000).toISOString()
    }],
    outgoing: []
  });

  appStore.saveTokens({
    tokensRemaining: 2,
    dailyLimit: 3,
    lastResetDate: startOfDay(new Date()).toISOString(),
    requestedDays: [{
      id: uuid(),
      doctorID: profile.id,
      doctorName: `${profile.firstName} ${profile.lastName}`,
      credential: profile.credential,
      hospitalID: HOSPITALS[1].id,
      hospitalName: HOSPITALS[1].name,
      date: dayAt(4).toISOString(),
      specialty: "Internal Medicine",
      status: "pending",
      requestedAt: new Date(Date.now() - 20 * 3600000).toISOString(),
      approvedAt: null,
      shiftRate: BASE_RATES["Internal Medicine"]
    }]
  });

}

/** A hospital with a live rota: open days, a roster, and approvals waiting. */
function seedHospital() {
  const hospital = HOSPITALS[0];
  appStore.saveHospitalProfile({
    id: hospital.id,
    userID: HOSPITAL_USER_ID,
    name: hospital.name,
    npi: "1902847365",
    email: "scheduling@riversidegeneral.org",
    verificationStatus: "verified",
    verificationFlags: [],
    priorityPosting: true,
    autoPay: false
  });

  seedMockDoctors();
  const roster = appStore.roster;

  // A staffed rota: three weeks of posted days, most already covered. Seeding
  // 30+ upcoming days also stops the app's generic filler from taking over.
  const specialties = [
    "Emergency Medicine", "Internal Medicine", "Cardiology", "Anesthesiology", "Surgery"
  ];
  const shifts = [];
  const openIndexes = new Set();
  let index = 0;
  for (let offset = 1; offset <= 21; offset++) {
    const date = dayAt(offset);
    const weekend = [0, 6].includes(date.getDay());
    for (const specialty of specialties) {
      const base = BASE_RATES[specialty] || 1200;
      shifts.push(makeShift(hospital, specialty, date, weekend ? base + 250 : base));
      // Leave a scattered handful open so the board has real work on it.
      if (index % 7 === 3) openIndexes.add(index);
      index++;
    }
  }
  appStore.saveShifts(shifts);

  appStore.saveAssignments(shifts
    .filter((_, i) => !openIndexes.has(i))
    .map((shift, i) => {
      const doctor = roster[i % roster.length];
      return {
        id: uuid(),
        shiftID: shift.id,
        shift,
        doctorID: doctor?.id || uuid(),
        doctorName: (doctor?.name || "Dr. Alex Rivera").replace(/^Dr\.\s*/, ""),
        status: "scheduled",
        assignedAt: new Date(Date.now() - 2 * 86400000).toISOString()
      };
    }));

  const pending = [
    { doctor: roster[2], specialty: "Emergency Medicine", offset: 3 },
    { doctor: roster[0], specialty: "Cardiology", offset: 5 },
    { doctor: roster[5], specialty: "Internal Medicine", offset: 8 }
  ].filter((r) => r.doctor);

  appStore.saveTokens({
    tokensRemaining: 3,
    dailyLimit: 3,
    lastResetDate: startOfDay(new Date()).toISOString(),
    requestedDays: pending.map(({ doctor, specialty, offset }) => ({
      id: uuid(),
      doctorID: doctor.id,
      doctorName: doctor.name.replace(/^Dr\.\s*/, ""),
      credential: doctor.credential,
      hospitalID: hospital.id,
      hospitalName: hospital.name,
      date: dayAt(offset).toISOString(),
      specialty,
      status: "pending",
      requestedAt: new Date(Date.now() - offset * 3600000).toISOString(),
      approvedAt: null,
      shiftRate: BASE_RATES[specialty] || 1200
    }))
  });

}

/** Signs into a fully populated local account. Never touches Supabase. */
export function startDemo(role) {
  resetLocalData();
  localStorage.setItem(DEMO_FLAG, "1");

  if (role === "Hospital") {
    beginSession({
      userID: HOSPITAL_USER_ID,
      email: "scheduling@riversidegeneral.org",
      role: "Hospital"
    });
    seedHospital();
  } else {
    beginSession({
      userID: DOCTOR_USER_ID,
      email: "m.ellison@riversidegeneral.org",
      role: "Doctor"
    });
    seedDoctor();
  }
}
