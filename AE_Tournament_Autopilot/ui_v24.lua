-- AE Tournament Brain V2.4 UI wrapper
local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/"
local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local ok,source=pcall(function()return game:HttpGet(ROOT.."ui_v23.lua?v24base="..nonce)end)
if not ok then error("V2.4 base UI fetch failed: "..tostring(source)) end
local chunk,err=loadstring(source)
if not chunk then error("V2.4 base UI compile failed: "..tostring(err)) end
local baseFactory=chunk()
if type(baseFactory)~="function" then error("V2.4 base UI factory missing") end

return function(Brain,opts)
    local UI=baseFactory(Brain,opts or {})
    if type(UI)~="table" then return UI end

    local function fmt(n)
        n=tonumber(n)
        if not n then return "?" end
        if math.abs(n)>=1000000 then return string.format("%.2fM",n/1000000) end
        if math.abs(n)>=1000 then return string.format("%.2fK",n/1000) end
        return string.format("%.0f",n)
    end

    local function patchVisibleText()
        local gui=UI.Gui
        if not gui then return end
        local state=Brain:GetState()
        local runtime=state and state.Runtime or (Brain.GetRuntimeV24 and Brain:GetRuntimeV24())
        for _,d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                if tostring(d.Text):find("TOURNAMENT BRAIN",1,true) then
                    d.Text=tostring(d.Text):gsub("V2%.3%-WM","V2.4-RUNTIME")
                elseif runtime and tostring(d.Text):match("^FARM ") then
                    if (runtime.FarmIncomePerWave or 0)>0 then
                        local level="?"
                        for _,u in pairs(runtime.FarmUnits or {}) do level=tostring(u.Upgrade or "?");break end
                        d.Text="FARM ACTIVE  ·  ¥"..fmt(runtime.FarmIncomePerWave).."/WAVE  ·  U"..level
                    end
                end
            end
        end
    end

    local oldRender=UI.Render
    if type(oldRender)=="function" then
        function UI:Render(...)
            local result=oldRender(self,...)
            patchVisibleText()
            return result
        end
    end

    patchVisibleText()
    return UI
end
