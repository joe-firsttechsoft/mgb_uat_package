// 檔名: list_collect_files.mjs
// 功能: 依 changes.csv 列出 export_files 資料夾底下應該被收集的檔案相對路徑（一行一個），
//       排除 src/test（保留例外）、fep-release-note、source/fep/** 的 .properties、
//       以及檔名未變的二進位資源檔（圖片／字型等，動作＝修改）。
//       排除規則與 generate_release_xlsx.mjs 共用同一份 release_exclude.mjs，
//       確保「異動清單」文件與實際收集的檔案彼此同步，不會各自維護出落差。
//       改用 changes.csv 驅動（而非直接掃 export_files 目錄），是因為「同檔名資源不列入」
//       這條規則需要「動作」欄位，單純掃檔案系統拿不到這個資訊。
// 使用: node list_collect_files.mjs <changes.csv> <export_files 資料夾>

import fs from "node:fs";
import path from "node:path";
import { parseCsv } from "./release_csv.mjs";
import { isExcludedPath } from "./release_exclude.mjs";

const [, , csvPath, srcDir] = process.argv;

if (!csvPath || !srcDir) {
  console.error("Usage: node list_collect_files.mjs <changes.csv> <export_files 資料夾>");
  process.exit(1);
}

if (!fs.existsSync(srcDir) || !fs.statSync(srcDir).isDirectory()) {
  console.error(`Source directory not found: ${srcDir}`);
  process.exit(1);
}

const csvText = fs.readFileSync(csvPath, "utf8").replace(/^﻿/, "");
const rows = parseCsv(csvText);

for (const row of rows) {
  if (row["動作"] === "刪除") continue; // 刪除的檔案本來就不會匯出到 export_files

  const relPath = path.posix.join(row["檔案路徑"], row["檔案名稱"]);
  if (isExcludedPath(relPath, row["動作"])) continue;

  const full = path.join(srcDir, relPath);
  if (fs.existsSync(full)) {
    console.log(relPath);
  }
}
