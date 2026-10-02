-- Pure hotkey binding rules. Keys are Enum.KeyCode names as strings. No engine globals.
local Rules = {}
-- Rebindable actions in the order the settings panel lists them.
Rules.Actions = {
 {id="build",name="建築頁",default="B"},
 {id="train",name="生產頁",default="T"},
 {id="research",name="科技頁／旋轉建築",default="R"},
 {id="formation",name="陣形頁",default="F"},
 {id="advanceAge",name="升級時代",default="U"},
 {id="stop",name="停止",default="X"},
 {id="garrison",name="駐紮／全部離開",default="G"},
 {id="delete",name="死亡／拆除",default="Delete"},
 {id="selectVillagers",name="選取所有村民",default="V"},
 {id="selectHome",name="選取主城",default="H"},
 {id="selectIdle",name="閒置村民",default="Period"},
 {id="gotoAlert",name="前往最近警報",default="Space"},
 {id="cameraUp",name="相機上移",default="W"},
 {id="cameraDown",name="相機下移",default="S"},
 {id="cameraLeft",name="相機左移",default="A"},
 {id="cameraRight",name="相機右移",default="D"},
}
-- Arrow keys, control groups, modifiers and cancel stay fixed, so the camera can always be
-- moved with the arrows whatever the four camera actions are bound to.
local reserved = {
 Up="相機移動",Down="相機移動",Left="相機移動",Right="相機移動",
 Home="回到基地",Escape="取消",
 One="編隊",Two="編隊",Three="編隊",Four="編隊",Five="編隊",Six="編隊",Seven="編隊",Eight="編隊",Nine="編隊",
 LeftShift="組合鍵",RightShift="組合鍵",LeftControl="組合鍵",RightControl="組合鍵",LeftAlt="組合鍵",RightAlt="組合鍵",
}
local labels = {Period=".",Comma=",",Semicolon=";",Quote="'",LeftBracket="[",RightBracket="]",BackSlash="\\",
 Minus="-",Equals="=",Zero="0",Delete="Del",Space="空白鍵",Backspace="Backspace",Insert="Ins",End="End",
 PageUp="PgUp",PageDown="PgDn"}
local allowed = {}
for code=string.byte("A"),string.byte("Z") do
 local key=string.char(code)
 if not reserved[key] then allowed[key]=true end
end
for key in pairs(labels) do allowed[key]=true end
local byId = {}
for _,action in ipairs(Rules.Actions) do byId[action.id]=action end

function Rules.action(id) return byId[id] end
function Rules.allowed(key) return type(key)=="string" and allowed[key]==true end
-- Why a key cannot be bound; nil when it can.
function Rules.rejectReason(key)
 if type(key)~="string" or key=="" or key=="Unknown" then return "無法辨識這個按鍵。" end
 if reserved[key] then return "這個按鍵固定用於"..reserved[key].."，不能改綁。" end
 if not allowed[key] then return "這個按鍵不能設為熱鍵。" end
 return nil
end
function Rules.label(key)
 if type(key)~="string" then return "?" end
 return labels[key] or key
end
function Rules.defaults()
 local map={}
 for _,action in ipairs(Rules.Actions) do map[action.id]=action.default end
 return map
end
function Rules.isDefault(map)
 for _,action in ipairs(Rules.Actions) do
  if type(map)~="table" or map[action.id]~=action.default then return false end
 end
 return true
end
function Rules.actionFor(map,key)
 if type(map)~="table" or type(key)~="string" then return nil end
 for _,action in ipairs(Rules.Actions) do
  if map[action.id]==key then return action.id end
 end
 return nil
end
-- Returns a new map. A key already used by another action is swapped with this action's old key,
-- so every action always keeps exactly one key.
function Rules.bind(map,id,key)
 if type(map)~="table" or not byId[id] then return nil,nil,"沒有這個熱鍵項目。" end
 local reason=Rules.rejectReason(key)
 if reason then return nil,nil,reason end
 local result={}
 for _,action in ipairs(Rules.Actions) do result[action.id]=map[action.id] end
 local other=Rules.actionFor(result,key)
 if other==id then return result,nil,nil end
 if other then result[other]=result[id] end
 result[id]=key
 return result,other,nil
end
function Rules.serialize(map)
 local parts={}
 for _,action in ipairs(Rules.Actions) do
  local key=type(map)=="table" and map[action.id] or nil
  parts[#parts+1]=action.id.."="..(Rules.allowed(key) and key or action.default)
 end
 return table.concat(parts,";")
end
-- Unknown actions and unusable keys are ignored; a stored value that leaves two actions on one
-- key is discarded as a whole.
function Rules.parse(text)
 local map=Rules.defaults()
 if type(text)~="string" or #text>512 then return map end
 for id,key in string.gmatch(text,"([%a]+)=([%a]+)") do
  if byId[id] and allowed[key] then map[id]=key end
 end
 local seen={}
 for _,action in ipairs(Rules.Actions) do
  local key=map[action.id]
  if seen[key] then return Rules.defaults() end
  seen[key]=true
 end
 return map
end
return Rules
