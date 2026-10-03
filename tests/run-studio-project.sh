#!/usr/bin/env bash
# 通用版：以命令列啟動 Studio 本機測試伺服器＋N 個客戶端執行任一驗證專案，收集指定標籤的紀錄（不需操作 Studio 視窗）。
# -task StartServer 固定讀 %LOCALAPPDATA%\Roblox\server.rbxl（Studio 每次 Play 都會覆寫的暫存檔），
# 這裡先備份、換成測試快照，伺服器載入後立刻還原。同一時間只能跑一個（共用 server.rbxl）。
# 用法：bash tests/run-studio-project.sh <專案.json> <標籤 grep 樣式> [客戶端數] [等待秒數] [輸出檔]
# 例：bash tests/run-studio-project.sh lobby-layout-validation.project.json 'LOBBY_LAYOUT' 1 120 tests/lobby-layout-studio-latest.txt
set -u
cd "$(dirname "$0")/.."
PROJECT="$1"
TAGS="$2"
PLAYERS="${3:-1}"
WAIT="${4:-150}"
NAME="$(basename "$PROJECT" .project.json)"
OUT="${5:-tests/$NAME-studio-latest.txt}"
R="$LOCALAPPDATA/Roblox"
EXE="$(ls -t "$R"/Versions/*/RobloxStudioBeta.exe | head -1)"
SNAPSHOT="build/AOE2-$NAME.rbxl"
MARK="C:/Users/user/Desktop/AOE2-finally/build/AOE2-$NAME.rbxlx"
./rojo.exe build "$PROJECT" -o "$SNAPSHOT" >/dev/null || exit 1
[ -e "$R/server.rbxl.$NAME-backup" ] && { echo "另一個執行中的備份存在：$R/server.rbxl.$NAME-backup"; exit 1; }
cp "$R/server.rbxl" "$R/server.rbxl.$NAME-backup" || exit 1
cp "$SNAPSHOT" "$R/server.rbxl"
START="$(date -u +%Y%m%dT%H%M%S)"
(cmd.exe //c start "" "$(cygpath -w "$EXE")" -creatorId 0 -placeVersion 0 -task StartServer -localProjectFile "$MARK" \
 -placeId 0 -universeId 0 -port 0 -creatorType 0 -numTestServerPlayersUponStartup "$PLAYERS" -baseUrl https://www.roblox.com \
 -channel production -instanceId StudioServer &)
sleep 20
cp "$R/server.rbxl.$NAME-backup" "$R/server.rbxl" && rm "$R/server.rbxl.$NAME-backup"
sleep "$WAIT"
: > "$OUT"
for f in $(ls "$R/logs" | grep "_Studio_" | sort); do
 t="$(echo "$f" | sed 's/.*_\(2026[0-9T]*\)Z_.*/\1/')"
 if [[ ! "$t" < "$START" ]] && sed -n 6p "$R/logs/$f" | grep -q "AOE2-$NAME.rbxlx -"; then
  echo "== $f" >> "$OUT"
  grep "CreatorOutput\|CreatorError\|CreatorWarning" "$R/logs/$f" \
   | grep "RTS\]\|$TAGS\|Script \|Stack\|ServerScriptService\|PlayerScripts\|ReplicatedStorage" \
   | sed 's/,[0-9.]*,[0-9a-f]*,[0-9]*,*[A-Za-z]* *\[FLog::Creator/ [/' >> "$OUT"
 fi
done
# 只關閉這次啟動的測試伺服器與它的客戶端。
powershell.exe -NoProfile -Command "\$p=Get-CimInstance Win32_Process -Filter \"name='RobloxStudioBeta.exe'\"; \$s=@(\$p | Where-Object { \$_.CommandLine -like '*StartServer*AOE2-$NAME.rbxlx*' }); \$ids=@(\$s | ForEach-Object ProcessId); \$c=@(\$p | Where-Object { \$_.CommandLine -like '*StartClient*' -and \$ids -contains \$_.ParentProcessId }); foreach (\$x in \$c+\$s) { Stop-Process -Id \$x.ProcessId -Force }"
cat "$OUT"
