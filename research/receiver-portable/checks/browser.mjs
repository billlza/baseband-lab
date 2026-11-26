import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir, release } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import { scenario } from "./device.mjs";
import { columns, readRows, stats, localOrigin } from "../Receiver/table.js";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.RECEIVER_PLAYWRIGHT || "playwright");
const root = fileURLToPath(new URL("../", import.meta.url));
const receipt = process.argv[2];
if (!receipt) throw Error("Pass the result JSON path.");
const cases = [
  "attached",
  "no-service",
  "nr",
  "guest",
  "wrong-model",
  "wrong-api",
  "invalid",
];
const wasmBytes = await readFile(path.join(root, "Receiver", "radio.wasm"));
const { instance } = await WebAssembly.instantiate(wasmBytes);
const w = instance.exports;
function normalize(body) {
  const payload = Buffer.from(body);
  const address = w.input_address();
  const buffer = new Uint8Array(w.memory.buffer, address, payload.length);
  buffer.set(payload);
  assert.equal(w.sample(payload.length, 0, 1795700000n), 0);
  assert.equal(
    new Uint8Array(w.memory.buffer, w.input_address(), payload.length).every(
      (n) => n === 0,
    ),
    true,
  );
  return new TextDecoder().decode(
    new Uint8Array(w.memory.buffer, w.output_address(), w.output_length()),
  );
}
const canonical = Object.fromEntries(
  cases.map((name) => [name, normalize(JSON.stringify(scenario(name)))]),
);
const rows = Object.fromEntries(
  Object.entries(canonical).map(([name, v]) => [name, readRows(v)[0].row]),
);
assert.equal(rows.attached.lte_sinr_db, "0.0");
assert.equal(rows.attached.nr_rsrp_dbm, "");
assert.equal(rows["no-service"].service, "no_service");
assert.equal(rows["no-service"].lte_rsrp_dbm, "");
assert.equal(rows.nr.nr_sinr_db, "8.0");
assert.equal(rows.guest.failure, "auth_failed");
assert.equal(rows["wrong-model"].failure, "unsupported");
assert.equal(rows["wrong-api"].failure, "unsupported");
assert.equal(rows.invalid.failure, "malformed");
assert.equal(readRows(normalize('{"session":'))[0].row.failure, "malformed");
assert.ok(!JSON.stringify(canonical).includes("SYNTHETIC_OMIT_FIELD"));
assert.equal(localOrigin("https://example.org/"), null);
assert.equal(localOrigin("http://192.168.1.1/"), "http://192.168.1.1");

let sequence = [],
  requests = [],
  outside = 0,
  unexpected = 0;
const server = createServer((req, res) => {
  if (req.url === "/") {
    res.writeHead(200, {
      "content-type": "text/html",
      "set-cookie": "synthetic=fixture; Path=/; SameSite=Strict; HttpOnly",
      "content-security-policy": "default-src 'self'; script-src 'none'",
    });
    res.end("<title>Local synthetic MR7450</title><h1>Receiver fixture</h1>");
    return;
  }
  if (req.url === "/api/model.json?internalapi=1") {
    requests.push({
      method: req.method,
      session: req.headers.cookie === "synthetic=fixture",
    });
    const mode = sequence.shift() ?? "attached";
    if (mode === "redirect") {
      res.writeHead(302, { location: "/elsewhere" });
      res.end();
      return;
    }
    if (mode === "http-error") {
      res.writeHead(503);
      res.end();
      return;
    }
    if (mode === "oversize") {
      res.writeHead(200, { "content-type": "application/json" });
      res.write(" ".repeat(700000));
      res.end(" ".repeat(550000));
      return;
    }
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify(scenario(mode)));
    return;
  }
  if (req.url === "/elsewhere") outside++;
  else if (req.url !== "/favicon.ico") unexpected++;
  res.writeHead(404);
  res.end();
});
await new Promise((ok, err) => {
  server.once("error", err);
  server.listen(0, "127.0.0.1", ok);
});
const site = "http://127.0.0.1:" + server.address().port;
const profile = await mkdtemp(path.join(tmpdir(), "m7-portable-"));
let context;
try {
  const extension = path.join(root, "Receiver");
  context = await chromium.launchPersistentContext(profile, {
    channel: "chromium",
    headless: true,
    acceptDownloads: true,
    args: [
      "--enable-unsafe-extension-debugging",
      "--disable-extensions-except=" + extension,
      "--load-extension=" + extension,
    ],
  });
  const target = context.pages()[0] || (await context.newPage());
  await target.goto(site);
  await target.bringToFront();
  const session = await context.newCDPSession(target);
  const browserSession = await context.browser().newBrowserCDPSession();
  const { targetInfos } = await browserSession.send("Target.getTargets", {
    filter: [{ type: "tab", exclude: false }],
  });
  const targetInfo =
    targetInfos.find((t) => t.url.startsWith(site + "/")) ||
    (targetInfos.length === 1 ? targetInfos[0] : null);
  assert.ok(targetInfo, "The isolated fixture tab must be identifiable");
  const worker =
    context.serviceWorkers()[0] ||
    (await context.waitForEvent("serviceworker", { timeout: 25000 }));
  assert.ok(
    await worker.evaluate(() => chrome.action.onClicked.hasListeners()),
    "Toolbar handler must be registered",
  );
  const id = new URL(worker.url()).hostname;
  const [panel] = await Promise.all([
    context.waitForEvent("page", { timeout: 15000 }),
    browserSession.send("Extensions.triggerAction", {
      id,
      targetId: targetInfo.targetId,
    }),
  ]);
  await panel.waitForLoadState();
  assert.ok(panel.url().startsWith("chrome-extension://" + id + "/panel.html"));
  assert.ok((await panel.locator("#target").innerText()).includes(site));
  async function collect(names, expected) {
    sequence = [...names];
    await panel.locator("#interval").fill("1");
    await panel.locator("#count").fill(String(names.length));
    await panel.getByRole("button", { name: "开始采样" }).click();
    await panel.waitForFunction(
      (n) =>
        document
          .getElementById("counts")
          .textContent.startsWith("共 " + n + " 次") &&
        !document.getElementById("start").disabled,
      expected,
      { timeout: 30000 },
    );
  }
  await collect(["attached", "no-service", "nr", "http-error", "guest"], 5);
  let downloaded = panel.waitForEvent("download");
  await panel.getByRole("button", { name: "导出 CSV" }).click();
  const file = await downloaded,
    csv = await readFile(await file.path(), "utf8");
  const rr = readRows(csv);
  assert.deepEqual(
    rr.map((x) => [x.row.outcome, x.row.service, x.row.failure]),
    [
      ["read", "attached", ""],
      ["read", "no_service", ""],
      ["read", "attached", ""],
      ["failed", "", "unreachable"],
      ["failed", "", "auth_failed"],
    ],
  );
  for (const [idx, k] of [
    [0, "attached"],
    [1, "no-service"],
    [2, "nr"],
    [4, "guest"],
  ])
    for (const key of columns.slice(2))
      assert.equal(rr[idx].row[key], rows[k][key]);
  assert.deepEqual(stats(rr, "lte_sinr_db"), { count: 2, median: 0 });
  assert.deepEqual(stats(rr, "nr_rsrp_dbm"), { count: 1, median: -91 });
  assert.ok(!csv.includes("SYNTHETIC_OMIT_FIELD"));
  await collect(["redirect"], 6);
  await collect(["wrong-model"], 7);
  await collect(["oversize"], 8);
  const second = panel.waitForEvent("download");
  await panel.getByRole("button", { name: "导出 CSV" }).click();
  const all = readRows(await readFile(await (await second).path(), "utf8"));
  assert.deepEqual(
    all.slice(5).map((x) => x.row.failure),
    ["auth_failed", "unsupported", "malformed"],
  );
  assert.equal(outside, 0);
  assert.equal(unexpected, 0);
  assert.equal(requests.length, 8);
  assert.ok(requests.every((r) => r.method === "GET" && r.session));
  const offline = await context.newPage();
  await offline.goto("chrome-extension://" + id + "/panel.html");
  await offline
    .locator("#input")
    .setInputFiles({
      name: "synthetic.csv",
      mimeType: "text/csv",
      buffer: Buffer.from(csv),
    });
  await offline.waitForFunction(() =>
    document.getElementById("counts").textContent.includes("共 5 次"),
  );
  const offlineRows = await offline.locator("tbody tr").allTextContents();
  assert.ok(offlineRows[2].endsWith("—02"));
  assert.ok(offlineRows[4].endsWith("—-911"));
  const viewer = await context.newPage(),
    remoteReads = [];
  viewer.on("request", (r) => {
    if (/^https?:/.test(r.url())) remoteReads.push(r.url());
  });
  await viewer.goto(pathToFileURL(path.join(root, "离线分析.html")).href);
  await viewer
    .locator("#file")
    .setInputFiles({
      name: "portable.csv",
      mimeType: "text/csv",
      buffer: Buffer.from(csv),
    });
  await viewer.waitForFunction(() =>
    document.getElementById("status").textContent.includes("5 次观测"),
  );
  assert.equal(
    await viewer.locator("tbody tr").nth(2).locator("td").last().innerText(),
    "2 / 5",
  );
  assert.equal(
    await viewer.locator("tbody tr").nth(4).locator("td").last().innerText(),
    "1 / 5",
  );
  await viewer.locator("#select").selectOption("nr_sinr_db");
  assert.equal(remoteReads.length, 0);
  const browserVersion = await session.send("Browser.getVersion");
  await writeFile(
    receipt,
    JSON.stringify(
      {
        os: process.platform,
        parser_sha256: createHash("sha256").update(wasmBytes).digest("hex"),
        release: release(),
        arch: process.arch,
        browser: browserVersion.product,
        fixture: "entirely synthetic, localhost",
        normal_toolbar_action: true,
        extension_samples: 8,
        normal_get_methods: true,
        read_ok: 3,
        failures: [
          "unreachable",
          "auth_failed",
          "auth_failed",
          "unsupported",
          "malformed",
        ],
        missing_nr_preserved: true,
        actual_zero_preserved: true,
        redirect_followed: outside,
        offline_csv_import: true,
        self_contained_file_viewer: true,
        file_viewer_network_requests: remoteReads.length,
        core_cases: cases.length,
        canonical: rows,
      },
      null,
      2,
    ) + "\n",
  );
  console.log("Receiver UI, eight polls, CSV and offline import passed.");
} finally {
  if (context) await context.close();
  await rm(profile, { recursive: true, force: true, maxRetries: 3 });
  await new Promise((ok) => server.close(ok));
}
