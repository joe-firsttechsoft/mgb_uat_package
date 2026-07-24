// 檔名: generate_release_xlsx.mjs
// 功能: 依 changes.csv 產生「兆豐UAT異動項目」xlsx，格式比照 outputs.0702 下的參考檔案
//       (異動清單 / 設定檔 / 資料庫異動[如有] / 模組更新 四張表)
// 使用: node generate_release_xlsx.mjs <changes.csv> <輸出.xlsx>

import ExcelJS from "exceljs";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import os from "node:os";
import path from "node:path";
import { isTestPath, isKeptTestFile, isFepReleaseNotePath } from "./release_exclude.mjs";
import { parseCsv } from "./release_csv.mjs";

const [, , csvPath, outPath] = process.argv;
const PROJECT_DIR = process.env.MGBFEP_PROJECT_DIR || path.join(os.homedir(), "Repo/idea_clone/mgbfep");
const SOURCE_FEP_DIR = path.join(PROJECT_DIR, "source/fep");

if (!csvPath || !outPath) {
  console.error("Usage: node generate_release_xlsx.mjs <changes.csv> <輸出.xlsx>");
  process.exit(1);
}

function ext(name) {
  const dot = name.lastIndexOf(".");
  return dot >= 0 ? name.slice(dot).toLowerCase() : "";
}

function isReleaseRow(row) {
  if (row["動作"] === "刪除") return false;
  // 異動清單只列 source/fep/ 下的異動，enclib/fep-enclib（另外打包成 jar 手動放入 fep-enchelper/lib）、
  // tools/fep-mock-server（內部測試工具）等不屬於實際交付給客戶的原始碼，不列入
  if (!row["檔案路徑"].startsWith("source/fep/")) return false;
  if (row["檔案路徑"].startsWith("source/SIT套config")) return false;
  if (row["檔案路徑"].startsWith("source/開發套config")) return false;
  if (isFepReleaseNotePath(row["檔案路徑"])) return false;
  if (isTestPath(row["檔案路徑"]) && !isKeptTestFile(row["檔案名稱"])) return false;
  // properties 例外：一般 resource properties（source/fep/**）跟 UAT套config 環境設定檔一律不列進異動清單，
  // 前者隨模組整包部署不需單獨列出，後者已經在「設定檔」分頁單獨列出
  if (ext(row["檔案名稱"]) === ".properties") return false;
  return true;
}

// UAT 均有 AP1/AP2 兩台備份機，config 一律同步部署到兩台，故主機欄位固定列出兩台
const HOST_BOTH = "UFEPAP01\n(172.29.1.11)\nUFEPAP02\n(172.29.1.12)";

// commit 路徑僅分兩種部署目標，其餘 properties 略過不列入設定檔
function deployPathForConfig(p) {
  if (!p.startsWith("source/UAT套config/")) return null;
  if (p.includes("/fep-web/was_config")) return "/fep/fep-web/was_config";
  if (p.includes("/config")) return "/fep/fep-app/config";
  return null;
}

function moduleNameFromPath(p) {
  const match = p.match(/^source\/fep\/([^/]+)/);
  return match ? match[1] : "";
}

// 一般原始碼模組（非封裝檔）：來源檔案為原始路徑，更新說明留白
function moduleRows(changedModules, excludeModules) {
  return [...changedModules]
    .filter((module) => !excludeModules.has(module))
    .sort((a, b) => a.localeCompare(b))
    .map((module) => ["AP1, AP2", module.toUpperCase(), `source/fep/${module}`, ""]);
}

// 讀取模組 pom.xml <dependencies> 內宣告的 fep-* 內部依賴（含 systemPath，不理會 scope）
function readPomFepDeps(moduleName) {
  let text;
  try {
    text = fsSync.readFileSync(path.join(SOURCE_FEP_DIR, moduleName, "pom.xml"), "utf8");
  } catch {
    return [];
  }
  // 排除 <dependencyManagement> 內的 <dependencies>（只管版本，非實際依賴），
  // 其餘（含 <profile> 內）的 <dependencies> 區塊都納入計算
  const withoutDepMgmt = text.replace(/<dependencyManagement>[\s\S]*?<\/dependencyManagement>/g, "");
  const blocks = [...withoutDepMgmt.matchAll(/<dependencies>[\s\S]*?<\/dependencies>/g)];
  const found = blocks.flatMap((block) =>
    [...block[0].matchAll(/<artifactId>(fep-[a-z0-9-]+)<\/artifactId>/g)].map((m) => m[1]),
  );
  return [...new Set(found)].filter((m) => m !== moduleName);
}

// 遞迴展開內部 fep-* 依賴，取得某個封裝模組（如 fep-server）完整的依賴子模組集合
function transitiveFepDeps(entryModule) {
  const seen = new Set([entryModule]);
  const queue = [entryModule];
  while (queue.length > 0) {
    const current = queue.shift();
    for (const dep of readPomFepDeps(current)) {
      if (!seen.has(dep)) {
        seen.add(dep);
        queue.push(dep);
      }
    }
  }
  seen.delete(entryModule);
  return seen;
}

// 更新說明依「來源檔案」判斷：是 *.tar.gz 就整包更新，其餘（如一般原始碼路徑）留白
function noteForFile(file) {
  return file.endsWith(".tar.gz") ? "全模組更新" : "";
}

// AP1/AP2 兆豐 UAT 專案實際部署的封裝檔（tar.gz），依 pom.xml 的 assembly 設定歸納：
// fep-server 全部 5 種變種都要列（atm/fisc/mb/hce/lateresponse）；fep-service 用 appmon/ems/cbstimeoutrerun 三種變種
// 這些封裝檔包含各自模組「遞迴展開後」的所有 fep-* 依賴，只要依賴的原始碼有異動就必須整包重新部署
const PACKAGE_DEFS = [
  { entryModule: "fep-server", label: "FEP-SERVER-ATM", file: "fep-server-bin-atm.tar.gz" },
  { entryModule: "fep-server", label: "FEP-SERVER-FISC", file: "fep-server-bin-fisc.tar.gz" },
  { entryModule: "fep-server", label: "FEP-SERVER-MB", file: "fep-server-bin-mb.tar.gz" },
  { entryModule: "fep-server", label: "FEP-SERVER-HCE", file: "fep-server-bin-hce.tar.gz" },
  { entryModule: "fep-server", label: "FEP-SERVER-LATERESPONSE", file: "fep-server-bin-lateresponse.tar.gz" },
  { entryModule: "fep-service", label: "FEP-SERVICE-APPMON", file: "fep-service-bin-appmon.tar.gz" },
  { entryModule: "fep-service", label: "FEP-SERVICE-EMS", file: "fep-service-bin-ems.tar.gz" },
  { entryModule: "fep-service", label: "FEP-SERVICE-CBSTIMEOUTRERUN", file: "fep-service-bin-cbstimeoutrerun.tar.gz" },
  { entryModule: "fep-batch", label: "FEP-BATCH", file: "fep-batch-bin.tar.gz" },
  { entryModule: "fep-batch-cmdline", label: "FEP-BATCH-CMDLINE", file: "fep-batch-cmdline-bin.tar.gz" },
];

// fep-web 沒有 tar.gz，是 war，更新說明固定寫「更新Web」
const WEB_MODULE = "fep-web";
const WEB_ROW = ["AP1, AP2", "FEP-WEB", "fep-web.war", "更新Web"];

// fep-batch-task 沒有單一封裝檔（每個 batch task 各自一個 jar），改本身有異動時固定寫死一列
const BATCH_TASK_MODULE = "fep-batch-task";
const BATCH_TASK_ROW = ["AP1, AP2", "FEP-BATCH-TASK", "/fep-assembly-batch-task", "底下所有task jar"];

function packageRows(changedModules) {
  const closureCache = new Map();
  const isTriggered = (entryModule) => {
    if (!closureCache.has(entryModule)) {
      closureCache.set(entryModule, transitiveFepDeps(entryModule));
    }
    const closure = closureCache.get(entryModule);
    return changedModules.has(entryModule) || [...closure].some((m) => changedModules.has(m));
  };

  const rowsOut = [];
  for (const def of PACKAGE_DEFS) {
    if (isTriggered(def.entryModule)) {
      rowsOut.push(["AP1, AP2", def.label, def.file, noteForFile(def.file)]);
    }
  }
  if (isTriggered(WEB_MODULE)) {
    rowsOut.push(WEB_ROW);
  }
  if (changedModules.has(BATCH_TASK_MODULE)) {
    rowsOut.push(BATCH_TASK_ROW);
  }
  return rowsOut;
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

// AP1/AP2 為同步部署的備份機，同一支 properties 在兩台上的異動合併成一列
const settingsMap = new Map();
for (const r of rows) {
  if (r["動作"] === "刪除") continue;
  if (ext(r["檔案名稱"]) !== ".properties") continue;
  const deployPath = deployPathForConfig(r["檔案路徑"]);
  if (!deployPath) continue;

  const key = `${r["檔案名稱"]}|${deployPath}`;
  if (!settingsMap.has(key)) {
    settingsMap.set(key, {
      file: r["檔案名稱"],
      path: deployPath,
      message: r["Commit Message"],
    });
  }
}
const settings = [...settingsMap.values()]
  .sort((a, b) => a.file.localeCompare(b.file) || a.path.localeCompare(b.path))
  .map((e) => [
    HOST_BOTH,
    "fepap",
    e.path,
    e.file,
    `${e.message}\n\n完整檔案路徑：${e.path}/${e.file}`,
  ]);
const dbRows = rows
  .filter((r) => ext(r["檔案名稱"]) === ".sql")
  .map((r, i) => [i + 1, r["檔案名稱"], r["檔案路徑"], r["動作"], r["Commit Message"]]);

// 測試檔排除清單：交付包（異動清單／收集檔案）一律排除 src/test，且交付方式是把新增/修改檔案
// 疊加到客戶既有環境，不會主動刪除任何檔案（含 git 上真的被刪除的檔案）。
// 這裡直接取未過濾的 rows，連「動作=刪除」的 src/test 異動都列出來，
// 讓客戶知道這次 commit 範圍動到了哪些測試路徑，可對照環境手動確認/刪除舊檔，避免跟新版原始碼不相容而編譯失敗。
const excludedTestRows = rows
  .filter((r) => isTestPath(r["檔案路徑"]) && !isKeptTestFile(r["檔案名稱"]))
  .map((r, i) => [i + 1, r["檔案名稱"], r["檔案路徑"], r["動作"], r["Commit Message"]]);

// 模組更新的模組清單，直接取自「異動清單」已過濾後的 changeRows，確保兩張表對得起來
const changedModules = new Set(
  changeRows
    .filter((r) => ext(r["檔案名稱"]) !== ".sql")
    .map((r) => moduleNameFromPath(r["檔案路徑"]))
    .filter(Boolean),
);
const modules = [
  ...packageRows(changedModules),
  ...moduleRows(changedModules, new Set([WEB_MODULE, BATCH_TASK_MODULE])),
].map((row, i) => [i + 1, ...row]);

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

if (excludedTestRows.length > 0) {
  const testSheet = workbook.addWorksheet("測試檔排除清單(需人工確認)");
  writeTable(
    testSheet,
    ["Index", "測試檔案", "位置", "異動類型", "Commit Message"],
    excludedTestRows,
    [8, 34, 72, 12, 100],
  );
}

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
    excludedTest: excludedTestRows.length,
    db: dbRows.length,
    modules: modules.length,
    outPath,
  }),
);
