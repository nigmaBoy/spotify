local MeshEngine = {}

function MeshEngine.Init(AudioPlayer, Players, RunService, MeshVisualizerPresets, getMeshEnabled)
    local MeshVisualizerFolder = Instance.new("Folder")
    MeshVisualizerFolder.Name = "SpotifyMeshVisualizer"
    MeshVisualizerFolder.Parent = workspace

    local MeshColorLayers = {}
    local meshCosTable, meshSinTable = {}, {}
    local meshTimeTracker = 0
    local meshRunningMaxVol = 150
    local meshSmoothLoudness = 0
    local meshRgbHue = 0

    local function lerpMeshStageColors(alpha)
        local stages = MeshVisualizerPresets.ColorStages
        local numStages = #stages
        if numStages == 1 then return stages[1] end
        local scaled = alpha * (numStages - 1) + 1
        local index1 = math.floor(scaled)
        local index2 = math.min(index1 + 1, numStages)
        local fraction = scaled - index1
        return stages[index1]:Lerp(stages[index2], fraction)
    end

    local function rebuildMeshTrigTables()
        meshCosTable, meshSinTable = {}, {}
        local segments = MeshVisualizerPresets.RadialSegments
        for s = 1, segments do
            local angle = (s / segments) * math.pi * 2
            meshCosTable[s] = math.cos(angle)
            meshSinTable[s] = math.sin(angle)
        end
    end

    local function RebuildMeshVisualizer()
        rebuildMeshTrigTables()
        for _, child in ipairs(MeshVisualizerFolder:GetChildren()) do
            child:Destroy()
        end
        table.clear(MeshColorLayers)
        local numLayers = MeshVisualizerPresets.NumColorLayers
        for i = 1, numLayers do
            local wf = Instance.new("WireframeHandleAdornment")
            wf.Name = "Layer_" .. i
            wf.Adornee = workspace.Terrain
            wf.AlwaysOnTop = false
            wf.Visible = getMeshEnabled()
            local ratio = numLayers > 1 and ((i - 1) / (numLayers - 1)) or 0
            if MeshVisualizerPresets.RGB then
                wf.Color3 = Color3.fromHSV(ratio, 1, 1)
            else
                wf.Color3 = lerpMeshStageColors(ratio)
            end
            wf.Parent = MeshVisualizerFolder
            table.insert(MeshColorLayers, wf)
        end
    end

    local function StartMeshVisualizer()
        return RunService.RenderStepped:Connect(function(deltaTime)
            if not getMeshEnabled() or #MeshColorLayers == 0 then return end
            local localPlayer = Players.LocalPlayer
            local hrp = localPlayer and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local presets = MeshVisualizerPresets
            local numRings = presets.NumRings
            local radialSegments = presets.RadialSegments
            local maxRadius = presets.MaxRadius
            local maxPeakHeight = presets.MaxPeakHeight
            local generalReactivity = presets.GeneralReactivity
            local centerReactivity = presets.CenterReactivity
            local outerReactivity = presets.OuterReactivity
            local edgeFalloffPower = presets.EdgeFalloffPower
            local numColorLayers = presets.NumColorLayers
            local maxColorIndex = numColorLayers - 1
            local invHeightRange = 1 / 1.8

            if presets.RGB then
                meshRgbHue = (meshRgbHue + deltaTime * 0.15) % 1
                for i = 1, #MeshColorLayers do
                    local ratio = numColorLayers > 1 and ((i - 1) / (numColorLayers - 1)) or 0
                    MeshColorLayers[i].Color3 = Color3.fromHSV((ratio * 0.5 + meshRgbHue) % 1, 1, 1)
                end
            end

            for i = 1, #MeshColorLayers do
                MeshColorLayers[i]:Clear()
            end

            local currentLoudness = (AudioPlayer.IsPlaying and AudioPlayer.PlaybackLoudness) or 0
            meshRunningMaxVol = math.max(currentLoudness, meshRunningMaxVol * 0.99)
            if meshRunningMaxVol < 150 then meshRunningMaxVol = 150 end

            local targetLoudness = math.clamp(currentLoudness / meshRunningMaxVol, 0, 1)
            meshSmoothLoudness = meshSmoothLoudness + (targetLoudness - meshSmoothLoudness) * 0.3

            meshTimeTracker = meshTimeTracker + deltaTime * (0.5 + meshSmoothLoudness * 0.8)
            local beatOffset = meshSmoothLoudness * 1.5

            local centerPos = hrp.Position - Vector3.new(0, presets.CenterOffsetY, 0)
            local centerY = centerPos.Y
            local gridVertices = {}

            for r = 1, numRings do
                gridVertices[r] = {}
                local radiusRatio = r / numRings
                local currentRadius = radiusRatio * maxRadius
                local edgeFactor = 1 - (radiusRatio ^ edgeFalloffPower)
                local centerBoost = centerReactivity - ((centerReactivity - outerReactivity) * radiusRatio)

                for s = 1, radialSegments do
                    local x = meshCosTable[s] * currentRadius
                    local z = meshSinTable[s] * currentRadius
                    local baseNoise = math.noise((x * 0.4) + beatOffset, (z * 0.4) - beatOffset, meshTimeTracker * 0.5)
                    local detailNoise = math.noise(x * 1.2, z * 1.2, meshTimeTracker)
                    local combined = math.clamp((baseNoise + detailNoise + 0.5) * 0.6, 0, 1)
                    local terrainShape = combined ^ 1.8
                    local targetHeight = (0.3 + (terrainShape * maxPeakHeight * meshSmoothLoudness * generalReactivity)) * centerBoost
                    local finalY = targetHeight * edgeFactor
                    gridVertices[r][s] = centerPos + Vector3.new(x, finalY, z)
                end
            end

            local centerRelativeHeight = gridVertices[1][1].Y - centerPos.Y
            local centerVertex = centerPos + Vector3.new(0, centerRelativeHeight, 0)

            for r = 1, numRings do
                for s = 1, radialSegments do
                    local nextS = (s % radialSegments) + 1
                    local p1 = gridVertices[r][s]
                    local p2 = gridVertices[r][nextS]

                    local avgY1 = (p1.Y + p2.Y) * 0.5 - centerY
                    local idx1 = math.floor(math.clamp(avgY1 * invHeightRange, 0, 1) * maxColorIndex) + 1
                    MeshColorLayers[idx1]:AddLine(p1, p2)

                    if r == 1 then
                        local avgY2 = (centerVertex.Y + p1.Y) * 0.5 - centerY
                        local idx2 = math.floor(math.clamp(avgY2 * invHeightRange, 0, 1) * maxColorIndex) + 1
                        MeshColorLayers[idx2]:AddLine(centerVertex, p1)
                    else
                        local pInner = gridVertices[r - 1][s]
                        local avgY3 = (pInner.Y + p1.Y) * 0.5 - centerY
                        local idx3 = math.floor(math.clamp(avgY3 * invHeightRange, 0, 1) * maxColorIndex) + 1
                        MeshColorLayers[idx3]:AddLine(pInner, p1)

                        local avgY4 = (pInner.Y + p2.Y) * 0.5 - centerY
                        local idx4 = math.floor(math.clamp(avgY4 * invHeightRange, 0, 1) * maxColorIndex) + 1
                        MeshColorLayers[idx4]:AddLine(pInner, p2)
                    end
                end
            end
        end)
    end

    return {
        Rebuild = RebuildMeshVisualizer,
        Start = StartMeshVisualizer,
        MeshColorLayers = MeshColorLayers
    }
end

return MeshEngine
