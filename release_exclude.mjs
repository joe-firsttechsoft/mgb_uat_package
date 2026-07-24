// 檔名: release_exclude.mjs
// 功能: src/test 與 fep-release-note 排除規則的唯一定義來源。
//       generate_release_xlsx.mjs（異動清單/模組更新）與 list_collect_files.mjs（實體收集檔案）
//       都透過本模組判斷是否排除，確保「文件」與「檔案」用同一份規則，不會各自維護漂移。

// 排除 src/test 邏輯比照 ../mgb-vul/RemoveTest.ps1：路徑落在 src/test/ 底下的一律排除，
// 但檔名包含下列關鍵字（不分大小寫）的例外保留（該 ps1 預設 Mode "1" 的行為）
const TEST_PATH_PATTERN = /(^|\/)src\/test\//;
const KEEP_TEST_NAME_PARTS = ["BatchTaskUtil", "Generator", "RemoveVersion"];

export function isTestPath(p) {
  return TEST_PATH_PATTERN.test(p);
}

export function isKeptTestFile(name) {
  const lower = name.toLowerCase();
  return KEEP_TEST_NAME_PARTS.some((part) => lower.includes(part.toLowerCase()));
}

export function isFepReleaseNotePath(p) {
  return p.includes("fep-release-note");
}

// source/fep/** 底下的一般模組內建 resource properties（打包進 jar，隨模組整包部署，
// 不是 source/UAT套config/ 下那種需要單獨列出來給客戶對照覆蓋的環境設定檔）
export function isFepModuleProperties(p) {
  return p.startsWith("source/fep/") && p.toLowerCase().endsWith(".properties");
}

// relPath: 相對於專案 repo root 的路徑（例如 source/fep/fep-server/src/test/xxx.java）
export function isExcludedPath(relPath) {
  const name = relPath.split("/").pop() ?? relPath;
  if (isFepReleaseNotePath(relPath)) return true;
  if (isTestPath(relPath) && !isKeptTestFile(name)) return true;
  if (isFepModuleProperties(relPath)) return true;
  return false;
}
