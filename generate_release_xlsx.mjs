// 檔名: generate_release_xlsx.mjs
// 功能: 依 changes.csv 產生「兆豐UAT異動項目」xlsx，格式比照 outputs.0702 下的參考檔案
//       (異動清單 / 設定檔 / 資料庫異動[如有] / 模組更新 四張表)
// 使用: node generate_release_xlsx.mjs <changes.csv> <輸出.xlsx>

import ExcelJS from "exceljs";
import fs from "node:fs/promises";

const [, , csvPath, outPath] = process.argv;

if (!csvPath || !outPath) {
  console.error("Usage: node generate_release_xlsx.mjs <changes.csv> <輸出.xlsx>");
  process.exit(1);
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    const next = text[i + 1];
    if (quoted) {
      if (ch === '"' && next === '"') {
        field += '"';
        i += 1;
      } else if (ch === '"') {
        quoted = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += ch;
    }
  }
  if (field || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  const headers = rows.shift();
  return rows
    .filter((r) => r.some((v) => v !== ""))
    .map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ""])));
}

function ext(name) {
  const dot = name.lastIndexOf(".");
  return dot >= 0 ? name.slice(dot).toLowerCase() : "";
}

function isReleaseRow(row) {
  if (row["動作"] === "刪除") return false;
  const allowed = new Set([".java", ".xml", ".html", ".js", ".properties", ".txt", ".jar", ".sql", ".css"]);
  if (!allowed.has(ext(row["檔案名稱"]))) return false;
  if (row["檔案路徑"].startsWith("source/SIT套config")) return false;
  if (row["檔案路徑"].startsWith("source/開發套config")) return false;
  if (row["檔案路徑"].startsWith("source/fep/fep-release-note")) return false;
  return true;
}

function hostForConfig(p) {
  if (p.includes("UAT_AP1")) return "UFEPAP01\n(172.29.1.11)";
  if (p.includes("UAT_AP2")) return "UFEPAP02\n(172.29.1.12)";
  return "";
}

function deployPathForConfig(p) {
  if (p.includes("/fep-web/was_config")) return "/fepap/fep-web/was_config";
  if (p.includes("/config")) return "/fepap/fep-app/config";
  return "";
}

function moduleNameFromPath(p) {
  const match = p.match(/^source\/fep\/([^/]+)/);
  return match ? match[1] : "";
}

function moduleRows(rows) {
  const grouped = new Map();
  for (const row of rows) {
    if (row["動作"] === "刪除") continue;
    if (ext(row["檔案名稱"]) === ".sql") continue;
    const module = moduleNameFromPath(row["檔案路徑"]);
    if (!module) continue;
    if (!grouped.has(module)) grouped.set(module, { count: 0, actions: new Set() });
    const entry = grouped.get(module);
    entry.count += 1;
    entry.actions.add(row["動作"]);
  }
  return [...grouped.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([module, entry], i) => [
      i + 1,
      "AP1, AP2",
      module.toUpperCase(),
      `source/fep/${module}`,
      `依異動清單更新，${entry.count} 個檔案，異動類型：${[...entry.actions].join("、")}`,
    ]);
}

function writeTable(sheet, headers, body, widths) {
  const headerRow = sheet.addRow(headers);
  headerRow.height = 22;
  headerRow.eachCell((cell) => {
    cell.font = { name: "微軟正黑體", size: 12, bold: true };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD9EAF7" } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    cell.border = {
      top: { style: "thin", color: { argb: "FFA6A6A6" } },
      bottom: { style: "thin", color: { argb: "FFA6A6A6" } },
      left: { style: "thin", color: { argb: "FFA6A6A6" } },
      right: { style: "thin", color: { argb: "FFA6A6A6" } },
    };
  });

  for (const values of body) {
    const row = sheet.addRow(values);
    const maxLen = Math.max(...values.map((v) => String(v ?? "").length));
    const maxLines = Math.max(...values.map((v) => String(v ?? "").split("\n").length));
    row.height = Math.min(160, Math.max(18, Math.ceil(maxLen / 70) * 16, maxLines * 16));
    row.eachCell((cell) => {
      cell.font = { name: "微軟正黑體", size: 12 };
      cell.alignment = { horizontal: "general", vertical: "top", wrapText: true };
      cell.border = {
        top: { style: "thin", color: { argb: "FFA6A6A6" } },
        bottom: { style: "thin", color: { argb: "FFA6A6A6" } },
        left: { style: "thin", color: { argb: "FFA6A6A6" } },
        right: { style: "thin", color: { argb: "FFA6A6A6" } },
      };
    });
  }

  sheet.columns.forEach((col, i) => {
    col.width = Math.max(6, Math.round((widths[i] ?? 20) / 7));
  });
  sheet.views = [{ state: "frozen", ySplit: 1 }];
  sheet.showGridLines = false;
}

const csvText = await fs.readFile(csvPath, "utf8");
const rows = parseCsv(csvText.replace(/^﻿/, ""));
const changeRows = rows.filter(isReleaseRow);
const settings = rows
  .filter((r) => r["動作"] !== "刪除" && r["檔案路徑"].startsWith("source/UAT套config/"))
  .map((r) => [
    hostForConfig(r["檔案路徑"]),
    "fepap",
    deployPathForConfig(r["檔案路徑"]),
    r["檔案名稱"],
    `${r["Commit Message"]}\n\n完整檔案路徑：${r["檔案路徑"]}/${r["檔案名稱"]}`,
  ]);
const dbRows = rows
  .filter((r) => ext(r["檔案名稱"]) === ".sql")
  .map((r, i) => [i + 1, r["檔案名稱"], r["檔案路徑"], r["動作"], r["Commit Message"]]);
const modules = moduleRows(rows);

const workbook = new ExcelJS.Workbook();

const changeSheet = workbook.addWorksheet("異動清單");
writeTable(
  changeSheet,
  ["Index", "修改檔案", "位置", "異動類型", "修改內容"],
  changeRows.map((r, i) => [i + 1, r["檔案名稱"], r["檔案路徑"], r["動作"], r["Commit Message"]]),
  [8, 34, 72, 12, 100],
);

const settingSheet = workbook.addWorksheet("設定檔");
writeTable(settingSheet, ["主機", "帳號", "路徑", "修改檔案", "修改內容"], settings, [24, 14, 30, 34, 100]);

if (dbRows.length > 0) {
  const dbSheet = workbook.addWorksheet("資料庫異動");
  writeTable(dbSheet, ["Index", "修改檔案", "位置", "異動類型", "修改內容"], dbRows, [8, 34, 72, 12, 100]);
}

const moduleSheet = workbook.addWorksheet("模組更新");
writeTable(moduleSheet, ["Index", "Server", "修改檔案", "來源檔案", "更新說明"], modules, [8, 18, 36, 42, 52]);

await workbook.xlsx.writeFile(outPath);

console.log(
  JSON.stringify({
    changes: changeRows.length,
    settings: settings.length,
    db: dbRows.length,
    modules: modules.length,
    outPath,
  }),
);
