// A fabricated receiver response. Payloads are built here; the test takes no field recording.
export function model() {
  return {
    session: { userRole: "Admin" },
    general: {
      model: "MR7450",
      apiVersion: "2.0",
      FWversion: "NTGX75_10.04.43.01",
      webAppVersion: "",
      upTime: 6000,
      devTemperature: 41,
    },
    power: {
      PMState: "Online",
      battChargeLevel: 75,
      batteryState: "Normal",
      charging: false,
      battChargeSource: "QuickCharge",
      batteryTemperature: 31,
    },
    sim: { SPN: "Research" },
    wwan: {
      connection: "Connected",
      currentNWserviceType: "Nr5gService",
      currentPSserviceType: "5GSUB6",
      registerNetworkDisplay: "Test Carrier",
      sessDuration: 1234,
      dataTransferredRx: "200",
      dataTransferredTx: "100",
      thermalState: "Normal",
      ca: { SCCcount: 0 },
      lteBandInfo: [{}],
      signalStrength: {
        rsrp: -100,
        rsrq: -14,
        sinr: 0,
        rssi: -70,
        nr5gRsrp: -32768,
        nr5gRsrq: -32768,
        nr5gSinr: -32768,
      },
    },
    wwanadv: { MCC: "001", MNC: "01", curBand: "LTE B7" },
    wifi: {
      enabled: false,
      status: "Off",
      guest: { status: "Off" },
      aux: { status: "Off" },
      clientCount: 0,
      offload: { enabled: false },
    },
    ethernet: { offload: { enabled: false } },
    router: { UPNPenabled: false },
    ra: { enabled: false },
    insight: { active: false },
    sms: { unreadMsgs: 0 },
    // Retained only by this in-memory synthetic device; must never appear in exported data.
    unusedNotes: "SYNTHETIC_OMIT_FIELD",
  };
}
export function scenario(name) {
  const m = model();
  if (name === "no-service") {
    m.wwan.connection = "Disconnected";
    m.wwan.registerNetworkDisplay = "";
  }
  if (name === "guest") return { session: { userRole: "Guest" } };
  if (name === "wrong-model") m.general.model = "MR1234";
  if (name === "wrong-api") m.general.apiVersion = "9.9";
  if (name === "invalid") m.wwan.signalStrength.rsrp = 200;
  if (name === "nr") {
    m.wwan.signalStrength.nr5gRsrp = -91;
    m.wwan.signalStrength.nr5gRsrq = -10;
    m.wwan.signalStrength.nr5gSinr = 8;
  }
  return m;
}
