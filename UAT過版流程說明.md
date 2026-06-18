# 兆豐 FEP 專案 SIT → UAT 過版流程說明

> 依據 `UAT過版程序.txt` 整理，並對照本 repo 內的 shell 腳本與 MGBFEP 專案相關程式碼。

## 整體流程概觀

文件分三大階段：

```mermaid
flowchart TD
    A[環境處理] --> B[過版資料處理]
    B --> C[過版清單整理]

    A --> A1[SQL DDL/DML 提前申請 DBA]
    A --> A2[MQ 新增提前申請]

    B --> B1[SIT commit cherry-pick 到 UAT]
    B --> B2[release.sh 產出過版包]
    B --> B3[匯入 Excel 過版清單並核對]
    B --> B4[更新兆豐 UAT 專案並 build.bat 驗證]
    B --> B5[檔案清洗 + email 兆豐]

    C --> C1[比對 SIT/UAT commit 差異]
    C --> C2[Excel 填入 UAT commit id]
    C --> C3[Git branch 打 tag]
```

---

## 一、環境處理（過版前準備）

| 步驟 | 說明 |
|------|------|
| SQL DDL/DML | 若有資料庫結構或資料異動，需**提早**提交兆豐 DBA，避免過版當天才發現衝突 |
| MQ 新增 | 若有新 Message Queue 設定，也需**提前申請** |

這是前置作業，與程式碼無直接關聯，但會影響 UAT 能否正常啟動。

---

## 二、過版資料處理（核心作業）

### 步驟 1：Git 合併 SIT → UAT

依據過版清單，將 SIT 的 commit **cherry-pick** 到 UAT。

- **分支命名**：`FEP_1-2_SIT`（開發測試）、`FEP_1-2_UAT`（兆豐 UAT）
- **方式**：優先用 **cherry-pick**（保留原始 commit message，方便追蹤）
- **衝突**：由 SD（Software Developer）處理

### 步驟 2：產出過版包（shell 腳本）

腳本位於本 repo 根目錄，需在 **Git repo root** 下執行（腳本會自動 `cd` 到 `git rev-parse --show-toplevel`）。

#### 腳本總覽

| 腳本 | 用途 | 呼叫方式 |
|------|------|----------|
| `release.sh` | **主流程**：一次完成匯出、Release Note、檔案收集 | `./release.sh <前一個過版 tag 或 commit>` |
| `export_commit_range.sh` | 匯出指定 commit 區間的變更檔案與 CSV | `./export_commit_range.sh <start> <end>` |
| `generate_release_note.sh` | 產生依模組分組的 Markdown Release Note | `./generate_release_note.sh <start_commit>` |
| `collect_files.sh` | 將 `export_files/` 扁平化收集到 `files/` | `./collect_files.sh`（需先執行匯出） |

> 原流程文件中的 `export_commit.sh` 對應實際檔名 **`export_commit_range.sh`**。

#### `release.sh` 執行流程

```bash
./release.sh <previous_release_tag_or_commit>
```

依序呼叫三支子腳本（`PREV_RELEASE` → `HEAD`）：

1. **`export_commit_range.sh`** — 匯出整個過版區間（若 `output/` 非空會詢問是否清空）
2. **`generate_release_note.sh`** — 補產 Release Note 文件
3. **`collect_files.sh`** — 扁平化收集檔案，方便交付

#### `export_commit_range.sh` 實際邏輯

```bash
# 批次過版（release.sh 內部呼叫）
./export_commit_range.sh <prev_release_tag_or_commit> HEAD

# 單一 commit 補過（原流程 A：之前漏過的單一 commit）
./export_commit_range.sh <該 commit 的前一個 commit> <該 commit>
```

**主要行為**：

| 項目 | 說明 |
|------|------|
| 工作目錄 | 切換到 Git repo root，確保路徑一致 |
| 輸出目錄 | 與腳本同路徑下的 `output/`（非 `release-note/` 子目錄） |
| `changes.csv` | 欄位：`檔案名稱,檔案路徑,動作,Commit Message`；動作含新增/修改/刪除/重新命名/複製 |
| `commits.csv` | 欄位：`Commit,Author,Date,Message`；涵蓋 `START~1..END` 區間（含 START 本身） |
| `changes.patch` | `git diff START END` 完整 patch |
| `export_files/` | 保留原始目錄結構；刪除的檔案不匯出；其餘以 `git show END:path` 取 END 版本內容 |

**檔案狀態處理**（`git diff --name-status -z`）：

- `A` → 新增、`M` → 修改、`D` → 刪除（不匯出實體檔）
- `R*` → 重新命名（取新檔名）
- `C*` → 複製（取新檔名）

#### `generate_release_note.sh` 產出

- 輸出：`output/FEP_RELEASE_NOTE_yyyy-mm-dd.md`
- 範圍：`START_COMMIT..HEAD`，**排除 merge commit**
- 依 `source/fep/` 下第三層路徑分組為 Module（例如 `fep-server`）
- 每個 Module 標題附統計：`(Added: N, Modified: N, Deleted: N, Renamed: N)`
- 每筆 commit 列出：短 hash、日期、subject，以及該 commit 的檔案變更清單

#### `collect_files.sh` 產出

- 來源：`output/export_files/`
- 目標：`output/files/`（**扁平化**，僅保留檔名）
- 同檔名會覆蓋；執行後會比對來源與收集後數量，若有差異會提示 filename overwrite

#### 完整 `output/` 目錄結構

```
output/
├── changes.csv          # 過版清單（匯入 Excel）
├── commits.csv          # commit 清單
├── changes.patch        # 完整 diff patch
├── export_files/        # 保留目錄結構的原始檔案
├── files/               # 扁平化後的交付用檔案
└── FEP_RELEASE_NOTE_yyyy-mm-dd.md
```

**特殊情況**（原流程）：

- **A.** 單一 commit 補過：直接呼叫 `export_commit_range.sh <前一個 commit> <目標 commit>`（不必跑完整 `release.sh`，或手動補跑 `generate_release_note.sh` / `collect_files.sh`）
- **B.** 若僅異動單一檔案且有相依性問題，需人工整理

### 步驟 3：核對過版清單

1. 將產出的 `changes.csv` 匯入 Excel 過版清單
2. 確認 Excel 清單與 `export_files/` 下檔案**數量、路徑一致**
3. 可用以下 Windows 指令列出檔案（路徑請依實際過版日期目錄調整）：

```cmd
:: 僅檔名（不含路徑）
for /r "C:\Users\essences\Desktop\Workspace\版本更新紀錄\P1-2_UAT\20260428\release-note\export_files\source\fep" %f in (*) do @echo %~nxf

:: 完整路徑 + 檔名
dir /s /b /a-d "C:\Users\essences\Desktop\Workspace\版本更新紀錄\P1-2_UAT\20260428\release-note\export_files\source\fep"
```

> 腳本預設輸出至 repo 內 `output/export_files/`；若交付前會複製到「版本更新紀錄」工作目錄，核對時以實際交付路徑為準。

### 步驟 4：Config 異動處理

若有 config 異動：

- 將相關資訊放置到「參數檔異動頁面」
- 將完整版 config 檔案集中放置，供客戶參考

### 步驟 5：Test 程式檔案處理

過版包中不應含一般 UT，但以下**必須保留**（截至 2026/03/24）：

| 類型 | 保留項目 |
|------|----------|
| RemoveVersion | fep-batch, fep-server, fep-service, fep-web 四個模組 |
| fep-batch-task | `AssemblyPropFileGenerator.java`, `ReleaseNoteGenerator.java` |

### 步驟 6：更新兆豐 UAT 專案並建置

將過版檔案套入兆豐 UAT 版專案，執行 `build.bat` 驗證：

**路徑**：`source/fep/build.bat`

```bat
@echo off
SET JAVA_HOME=D:/Java/ibm-semeru-open-jdk_x64_windows_17.0.5_8_openj9-0.35.0
SET MAVEN_HOME=D:/Development/apache-maven-3.8.5
SET PATH=%PATH%;%JAVA_HOME%/bin;%MAVEN_HOME%/bin
call mvn clean install -Dmaven.repo.local=E:/maven/repository -f pom.xml
call mvn clean install -Dmaven.repo.local=E:/maven/repository -pl fep-web -Pwar
```

**特殊注意事項**：

| 情況 | 處理方式 |
|------|----------|
| fep-web.war 異動 | 建議先放到 29 測試環境確認能否啟動 |
| enclib 異動 | 需先在自家 UAT branch `enclib/fep-enclib` 打包，取得 `fep-enclib.jar` 後放到 `source/fep/fep-enchelper/lib/` |

**enclib JAR 可能來源**：

1. `enclib/fep-enclib/target/fep-enclib-1.0.0.jar`
2. `source/fep/fep-enchelper/lib/fep-enclib.jar`
3. `source/fep-assembly-library/fep-enclib.jar`
4. 隨過版清單提供給兆豐，包版前預先放到 `source/fep/fep-enchelper/lib/`

### 步驟 7：檔案清洗 + Email 兆豐

最後清理過版包（移除不必要檔案），email 給兆豐做正式紀錄。

---

## 三、過版清單整理（事後追蹤）

### Git 指令：比較 SIT / UAT 差異

重點：**`git cherry` 比的是「內容」，不是「歷史」**。

| 指令 | 意義 |
|------|------|
| `git cherry -v FEP_1-2_UAT FEP_1-2_SIT \| grep '^+'` | SIT 有、UAT **還沒有**的 commit（內容層級） |
| `git cherry -v FEP_1-2_UAT FEP_1-2_SIT \| grep '-'` | SIT 的 commit **內容已在 UAT**（含 cherry-pick、rebase、patch 相同） |
| `git log FEP_1-2_UAT..FEP_1-2_SIT --oneline` | SIT 有但 UAT **歷史上沒有**的 commit（可能漏算 cherry-pick） |
| `git log FEP_1-2_UAT..FEP_1-2_SIT --pretty=format:"%h %an %ad %s" --date=short` | 同上，含 author、date（可能不包含 cherry-pick、rebase、squash merge） |

**實用組合**（列出未進 UAT 的 commit 詳情）：

```bash
git cherry -v FEP_1-2_UAT FEP_1-2_SIT | grep '^+' | \
  awk '{print $2}' | \
  xargs -I {} git show -s --format="%h%x09%an%x09%ad%x09%s" --date=short {}
```

輸出欄位：commit hash、author、date、commit message。

### 後續步驟

1. 匯入 Excel，篩出未進 UAT 的項目
2. 依 commit message 在 UAT branch 找對應 commit id
3. 依 SIT commit 查找線上過版清單，填入 UAT commit id，並更新過版日期
4. 在 Git branch **打 tag** 紀錄本次過版

---

## 四、專案中相關程式碼

### 1. `RemoveVersion.java` — 移除 JAR 版本號

**模組**：fep-batch、fep-server、fep-service、fep-web

**路徑範例**：`source/fep/fep-server/src/test/java/com/syscom/fep/server/build/RemoveVersion.java`

**邏輯**：將 `fep-xxx-1.0.0.jar` 重新命名為 `fep-xxx.jar`。

```java
// 定位到 WEB-INF/lib
File lib = new File(target, "/fep-server/WEB-INF/lib");
// 匹配 fep-*-1.0.0.jar
FileFilter filefilter = new RegexFileFilter("^fep-(.*)-1.0.0.jar", IOCase.INSENSITIVE);
// 重新命名：去掉 -1.0.0
Files.move(sourceFile.toPath(), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
```

**用途**：兆豐部署環境可能不帶版本號的 JAR 名稱，此 UT 在 build 後自動處理。

### 2. `AssemblyPropFileGenerator.java` — 自動產生 batch task 組態

**模組**：fep-batch-task

**路徑**：`source/fep/fep-batch-task/src/test/java/com/syscom/fep/batch/task/util/AssemblyPropFileGenerator.java`

**邏輯**：

1. 掃描 `classes/com/syscom/fep/batch/task/` 下所有 batch task class
2. 產生 `assembly-prop-batch-tasks=TaskA,\TaskB,\...`
3. 寫入 `fep-config/src/main/assembly/fep-batch-task/assembly-batch-task-prop.properties`

**用途**：新增 batch task 時，自動更新 assembly 組態，避免手動維護。

### 3. `ReleaseNoteGenerator.java` — 自動產生 Release Note 模板

**模組**：fep-batch-task

**路徑**：`source/fep/fep-batch-task/src/test/java/com/syscom/fep/batch/task/util/ReleaseNoteGenerator.java`

**邏輯**：

1. 掃描 batch task class
2. 為每個 task 產生 `fep-batch-task-{TaskName}.txt`
3. 放到 `fep-release-note/` 目錄

**用途**：為每個 batch task 建立 release note 模板，供過版文件填寫。

### 4. Maven Surefire 設定 — 保留特定 UT

**fep-batch-task**（`pom.xml`）：

```xml
<configuration>
    <includes>
        <include>**/AssemblyPropFileGenerator.java</include>
        <include>**/ReleaseNoteGenerator.java</include>
    </includes>
</configuration>
```

**fep-batch / fep-server / fep-service / fep-web** 的 `pom.xml` 也有類似設定，只執行 `RemoveVersion.java`。

---

## 五、流程與工具對照表

| 文件步驟 | 相關工具 / 程式 |
|----------|-----------------|
| cherry-pick SIT → UAT | Git 指令 |
| 產出過版包（主流程） | `release.sh` |
| 匯出 commit 區間檔案 | `export_commit_range.sh` → `changes.csv`、`commits.csv`、`changes.patch`、`export_files/` |
| 產生 Release Note | `generate_release_note.sh` → `FEP_RELEASE_NOTE_yyyy-mm-dd.md` |
| 扁平化交付檔案 | `collect_files.sh` → `output/files/` |
| 建置驗證 | `source/fep/build.bat` → Maven clean install |
| 移除 JAR 版本號 | `RemoveVersion.java`（四模組） |
| 更新 batch task 組態 | `AssemblyPropFileGenerator.java` |
| 產生 release note 模板 | `ReleaseNoteGenerator.java`（batch task UT，與 shell 的 `generate_release_note.sh` 不同） |
| enclib 打包 | `enclib/fep-enclib/build.bat` |
| 比對 commit 差異 | `git cherry` / `git log` 指令 |

---

## 六、過版檢查清單（Checklist）

### 過版前

- [ ] SQL DDL/DML 已提交兆豐 DBA
- [ ] MQ 新增已提前申請
- [ ] 過版清單已確認（SIT commit 列表）

### 過版中

- [ ] SIT commit 已 cherry-pick 到 UAT（衝突已解）
- [ ] `release.sh` 已產出完整 `output/`（或單一 commit 已用 `export_commit_range.sh` 補過）
- [ ] `changes.csv` / `commits.csv` 與 `export_files/` 數量、路徑一致
- [ ] `FEP_RELEASE_NOTE_yyyy-mm-dd.md` 已產生並檢視
- [ ] Config 異動已整理到參數檔異動頁面
- [ ] 不必要 UT 已移除（保留 RemoveVersion、Generator 類）
- [ ] 兆豐 UAT 專案 `build.bat` 建置成功
- [ ] fep-web.war 已在 29 環境驗證（若有異動）
- [ ] enclib JAR 已更新（若有異動）

### 過版後

- [ ] 過版包已清洗並 email 兆豐
- [ ] 線上過版清單已更新 UAT commit id、過版日期
- [ ] Git branch 已打 tag
