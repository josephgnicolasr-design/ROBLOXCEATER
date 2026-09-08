--!strict
-- Abyssal — UI Theme tokens (client).
-- Single visual source for all UI views. Readability-first: never bare text on
-- water (every label sits on a panel or carries a stroke), body >= 18px on
-- panels, numbers get stroke + high-contrast fill, touch targets >= 44px.

local Theme = {}

-- GDD §4 water: near-black teal base, glowing accents.
Theme.Colors = {
    Base = Color3.fromRGB(2, 12, 15),
    Panel = Color3.fromRGB(6, 34, 42),
    PanelEdge = Color3.fromRGB(45, 212, 191),
    Teal = Color3.fromRGB(45, 212, 191),
    Cyan = Color3.fromRGB(34, 211, 238),
    Gold = Color3.fromRGB(251, 191, 36),
    Red = Color3.fromRGB(239, 68, 68),
    Green = Color3.fromRGB(74, 222, 128),
    Text = Color3.fromRGB(232, 246, 245),
    Dim = Color3.fromRGB(159, 184, 181),
    Ink = Color3.fromRGB(2, 12, 15),
    Rare = Color3.fromRGB(168, 85, 247),
}

Theme.Fonts = {
    Bold = Enum.Font.GothamBold,
    Regular = Enum.Font.Gotham,
}

-- Point sizes. Body floor is 18 on panels; HUD numbers 20+; bite "!" is 96.
Theme.Sizes = {
    Body = 18,
    Small = 16,
    Number = 22,
    Title = 28,
    Bite = 96,
    TouchMin = 44, -- minimum touch target edge (px)
}

Theme.Transparency = {
    Panel = 0.22, -- panel background (still occludes water behind text)
    Pill = 0.15,
    Faint = 0.45,
}

-- Generic constructor: Theme.make("TextLabel", { Parent = ..., Text = ... }).
function Theme.make(className: string, props: { [string]: any }): Instance
    local inst = Instance.new(className)
    for k, v in props do
        if k ~= "Parent" then
            local ok = pcall(function()
                (inst :: any)[k] = v
            end)
            if not ok then
                warn("[AbyssalUI] bad prop " .. tostring(k) .. " on " .. className)
            end
        end
    end
    if props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

-- Rounded dark panel behind any floating text (the "never bare text" rule).
function Theme.panel(frame: GuiObject?, edge: boolean?)
    if frame == nil then
        return
    end
    (frame :: any).BackgroundColor3 = Theme.Colors.Panel
    (frame :: any).BackgroundTransparency = Theme.Transparency.Panel
    (frame :: any).BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    if edge == true then
        local stroke = Instance.new("UIStroke")
        stroke.Color = Theme.Colors.PanelEdge
        stroke.Transparency = 0.35
        stroke.Thickness = 2
        stroke.Parent = frame
    end
end

-- Number treatment: bright fill + dark stroke (+ optional glow stroke).
function Theme.stroke(label: GuiObject?, glow: Color3?)
    if label == nil then
        return
    end
    local s = Instance.new("UIStroke")
    s.Color = Theme.Colors.Ink
    s.Thickness = 2
    s.Transparency = 0.15
    s.Parent = label
    if glow then
        local g = Instance.new("UIStroke")
        g.Color = glow
        g.Thickness = 4
        g.Transparency = 0.75
        g.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        g.Parent = label
    end
end

return Theme
