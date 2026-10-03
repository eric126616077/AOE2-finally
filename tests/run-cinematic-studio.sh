#!/usr/bin/env bash
# 以命令列啟動 Studio 本機測試伺服器＋1 客戶端播放戰鬥預告片（cinematic/*.lua），收集 [TRAILER] 與 [TRAILER_SHOT] 紀錄（不需操作 Studio 視窗）。
# -task StartServer 固定讀 %LOCALAPPDATA%\Roblox\server.rbxl（Studio 每次 Play 都會覆寫的暫存檔），
# 這裡先備份、換成測試快照，伺服器載入後立刻還原。用法：bash tests/run-cinematic-studio.sh [等待秒數] [輸出檔]
set -u
cd "$(dirname "$0")/.."
WAIT="${1:-150}"
OUT="${2:-tests/cinematic-studio-latest.txt}"
R="$LOCALAPPDATA/Roblox"
EXE="$(ls -t "$R"/Versions/*/RobloxStudioBeta.exe | head -1)"
SNAPSHOT="build/AOE2-cinematic.rbxl"
MARK="C:/Users/user/Desktop/AOE2-finally/build/AOE2-cinematic.rbxlx"
./rojo.exe build cinematic.project.json -o "$SNAPSHOT" >/dev/null || exit 1
cp "$R/server.rbxl" "$R/server.rbxl.cinematic-backup" || exit 1
cp "$SNAPSHOT" "$R/server.rbxl"
START="$(date -u +%Y%m%dT%H%M%S)"
(cmd.exe //c start "" "$(cygpath -w "$EXE")" -creatorId 0 -placeVersion 0 -task StartServer -localProjectFile "$MARK" \
 -placeId 0 -universeId 0 -port 0 -creatorType 0 -numTestServerPlayersUponStartup 1 -baseUrl https://www.roblox.com \
 -channel production -instanceId StudioServer &)
sleep 20
cp "$R/server.rbxl.cinematic-backup" "$R/server.rbxl" && rm "$R/server.rbxl.cinematic-backup"
sleep "$WAIT"
: > "$OUT"
for f in $(ls "$R/logs" | grep "_Studio_" | sort); do
 t="$(echo "$f" | sed 's/.*_\(2026[0-9T]*\)Z_.*/\1/')"
 if [[ ! "$t" < "$START" ]] && sed -n 6p "$R/logs/$f" | grep -q "AOE2-cinematic.rbxlx -"; then
  echo "== $f" >> "$OUT"
  grep "CreatorOutput\|CreatorError\|CreatorWarning" "$R/logs/$f" \
   | grep "RTS\]\|TRAILER\|Script \|Stack\|ServerScriptService\|PlayerScripts\|ReplicatedStorage" \
   | sed 's/,[0-9.]*,[0-9a-f]*,[0-9]*,*[A-Za-z]* *\[FLog::Creator/ [/' >> "$OUT"
 fi
done
# 只關閉這次啟動的測試伺服器與它的客戶端。
powershell.exe -NoProfile -Command "\$p=Get-CimInstance Win32_Process -Filter \"name='RobloxStudioBeta.exe'\"; \$s=@(\$p | Where-Object { \$_.CommandLine -like '*StartServer*AOE2-cinematic.rbxlx*' }); \$ids=@(\$s | ForEach-Object ProcessId); \$c=@(\$p | Where-Object { \$_.CommandLine -like '*StartClient*' -and \$ids -contains \$_.ParentProcessId }); foreach (\$x in \$c+\$s) { Stop-Process -Id \$x.ProcessId -Force }"
cat "$OUT"
