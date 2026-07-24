// 檔名: list_collect_files.mjs
// 功能: 列出 export_files 資料夾底下、排除 src/test（保留例外）、fep-release-note、
//       source/fep/** 的 .properties 後應該被收集的檔案相對路徑（一行一個），供 collect_files.sh 使用。
//       排除規則與 generate_release_xlsx.mjs 共用同一份 release_exclude.mjs，
//       確保「異動清單」文件與實際收集的檔案彼此同步，不會各自維護出落差。
// 使用: node list_collect_files.mjs <export_files 資料夾>

import fs from "node:fs";
import path from "node:path";
import { isExcludedPath } from "./release_exclude.mjs";

const [, , srcDir] = process.argv;

if (!srcDir) {
  console.error("Usage: node list_collect_files.mjs <export_files 資料夾>");
  process.exit(1);
}

if (!fs.existsSync(srcDir) || !fs.statSync(srcDir).isDirectory()) {
  console.error(`Source directory not found: ${srcDir}`);
  process.exit(1);
}

function walk(dir, base) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, base);
    } else if (entry.isFile()) {
      const rel = path.relative(base, full).split(path.sep).join("/");
      if (!isExcludedPath(rel)) {
        console.log(rel);
      }
    }
  }
}

walk(srcDir, srcDir);
