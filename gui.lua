-- Process the single packet queue even if UI is hidden
function ProcessSinglePacketQueue()
    if singlePacketQueue ~= nil and #singlePacketQueue > 0 then
        local delay = gSettings.PacketSearchDelay or 1.5
        if os.clock() >= singlePacketNextSend then
            local entry = table.remove(singlePacketQueue, 1)
            if entry then
                local packet = struct.pack('LL', 0, bit.band(entry.Id, 0x7FF))
                AshitaCore:GetPacketManager():AddOutgoingPacket(0x16, packet:totable())
                print(chat.header('ScentHound') .. chat.message(string.format('Sent update request packet for %s.', entry:ToString())))
            end
            singlePacketNextSend = os.clock() + delay
        end
        if #singlePacketQueue == 0 then
            singlePacketQueue = nil
            print(chat.header('ScentHound') .. chat.message('All packets sent.'))
        end
    end
end

local zoneDat = require('zonedat');
local imgui = require('imgui');

local isOpen = { false };
local trackSelection = -1;
local zoneSelection = -1;
local sortedTrack = T {};
local sortedZone = T {};
local searchResults = T {};
local gui = {};



local profileNameBuffer = { '' }
local selectedProfile = 1
local getProfileNames, saveCurrentProfile, loadProfile, deleteProfile
local profileInputModal = { visible = false, alreadyExisting = false, input = { '' } }
local profileConfirmModal = { visible = false, action = '', name = '' }

function gui:Init()
    if not gSettings.EntityColors then gSettings.EntityColors = {} end
    if not gSettings.Profiles then gSettings.Profiles = {} end
    if not gSettings.LastProfile then gSettings.LastProfile = '' end

    function getProfileNames()
        local names = {}
        for name, _ in pairs(gSettings.Profiles) do
            table.insert(names, name)
        end
        table.sort(names)
        return names
    end

    function saveCurrentProfile(name)
        if not name or name == '' then return end
        gSettings.Profiles[name] = {}
        for id, _ in pairs(gSettings.Monitored) do
            gSettings.Profiles[name][id] = true
        end
        gSettings.LastProfile = name
        settings.save()
        print(chat.header('ScentHound') .. chat.message('Profile saved: ' .. name))
    end

    function isValidMob(obj)
        return type(obj) == 'table' and type(obj.Name) == 'string' and obj.Name ~= '' and obj.Id ~= nil
    end

    function sortPredicate(a, b)
        if not isValidMob(a) and not isValidMob(b) then return false end
        if not isValidMob(a) then return false end
        if not isValidMob(b) then return true end
        if a.Name ~= b.Name then
            return a.Name < b.Name
        end
        return a.Id < b.Id
    end

    function RebuildTracking()
        sortedTrack = T {}
        for _, entry in pairs(gZoneList) do
            if gSettings.Monitored[entry.Id] ~= nil and isValidMob(entry) then
                -- Load color from settings if present
                if gSettings.EntityColors and gSettings.EntityColors[entry.Id] then
                    entry.Color = gSettings.EntityColors[entry.Id]
                end
                sortedTrack:append(entry)
            end
        end
        if #sortedTrack > 1 then
            table.sort(sortedTrack, sortPredicate)
        end
    end

    function loadProfile(name)
        if not name or not gSettings.Profiles[name] then return end
        gSettings.Monitored = T {}
        for id, _ in pairs(gSettings.Profiles[name]) do
            local mob = gZoneList and gZoneList[id]
            if mob then
                gSettings.Monitored[id] = mob
            end
        end
        gSettings.LastProfile = name
        settings.save()
        RebuildTracking()
        print(chat.header('ScentHound') .. chat.message('Profile loaded: ' .. name))
    end

    function deleteProfile(name)
        if not name or not gSettings.Profiles[name] then return end
        gSettings.Profiles[name] = nil
        if gSettings.LastProfile == name then
            gSettings.LastProfile = ''
            gSettings.Monitored = T {}
            RebuildTracking()
        end
        settings.save()
        print(chat.header('ScentHound') .. chat.message('Profile deleted: ' .. name))
    end
end

local identifierOptions = T { 'Index (Decimal)', 'Index (Hex)', 'Id (Decimal)', 'Id (Hex)' };
local searchInput = T { '' };



local function ColorSelector(container, key)
    --Credit: Atom0s for color flip function from equipmon
    local function cflip(c)
        local r, b = c[3], c[1]
        c[1] = r
        c[3] = b
        return c
    end
    local colors = cflip({ imgui.ColorConvertU32ToFloat4(container[key]) })
    if (imgui.ColorEdit4('Color', colors)) then
        colors = cflip(colors)
        container[key] = imgui.ColorConvertFloat4ToU32(colors)
        gUpdate = true
        gUpdateTimer = os.clock() + 5
    end
end

function gui:SetZone(zone, subZone)
    gZoneList = zoneDat:Load(zone, subZone)
    sortedZone = T {}
    for id, mob in pairs(gZoneList) do
        if isValidMob(mob) then
            sortedZone:append(mob)
        end
    end
    if #sortedZone > 1 then
        table.sort(sortedZone, sortPredicate)
    end
    trackSelection = -1
    zoneSelection = -1
    RebuildTracking()
    gui:UpdateSearch()
end

function gui:UpdateSearch()
    searchResults = T {};
    if searchInput[1] == '' then
        searchResults = sortedZone;
    else
        for _, entry in ipairs(sortedZone) do
            if string.find(string.lower(entry:ToString()), string.lower(searchInput[1]), 1, true) then
                searchResults:append(entry);
            end
        end
        table.sort(searchResults, sortPredicate);
    end

    if zoneSelection > #searchResults then
        zoneSelection = -1;
    end
end

function gui:Show()
    isOpen[1] = true;
end

function gui:Tick()
    if isOpen[1] == false then return end

    if (imgui.Begin('ScentHound##Scenthound_MainWindow', isOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
        local profileNames = getProfileNames()
        table.insert(profileNames, 1, 'None')
        local currentProfile = gSettings.LastProfile or ''
        local comboIndex = 1
        if currentProfile == '' or not gSettings.Profiles[currentProfile] then
            comboIndex = 1
        else
            for i = 2, #profileNames do
                if profileNames[i] == currentProfile then
                    comboIndex = i
                    break
                end
            end
        end
        local comboWidth = 200
        imgui.SetNextItemWidth(comboWidth)
        if imgui.BeginCombo('##ProfileCombo', profileNames[comboIndex] or 'None') then
            for i, name in ipairs(profileNames) do
                if imgui.Selectable(name, comboIndex == i) then
                    comboIndex = i
                    if name == 'None' then
                        gSettings.LastProfile = ''
                        gSettings.Monitored = T {}
                        settings.save()
                        RebuildTracking()
                    elseif gSettings.Profiles[name] then
                        loadProfile(name)
                    end
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        if imgui.Button('New', { 70, 0 }) then
            profileInputModal.input[1] = ''
            profileInputModal.alreadyExisting = false
            profileInputModal.visible = true
        end
        imgui.SameLine()
        if imgui.Button('Delete', { 70, 0 }) then
            if profileNames[comboIndex] then
                profileConfirmModal.action = 'delete'
                profileConfirmModal.name = profileNames[comboIndex]
                profileConfirmModal.visible = true
            end
        end

        if profileInputModal.visible then
            imgui.OpenPopup('New Profile')
        end
        if imgui.BeginPopupModal('New Profile', nil, ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.Text('Enter a name for the new profile:')
            imgui.SetNextItemWidth(-1)
            if imgui.InputText('##NewProfileName', profileInputModal.input, 64) then
                if profileInputModal.input[1] == '' then
                    profileInputModal.alreadyExisting = false
                end
            end
            if profileInputModal.alreadyExisting then
                imgui.TextColored({ 1, 0, 0, 1 }, 'A profile with this name already exists!')
            end
            if imgui.Button('OK', { 80, 0 }) then
                local name = profileInputModal.input[1]
                if name and name ~= '' then
                    if gSettings.Profiles[name] then
                        profileInputModal.alreadyExisting = true
                    else
                        saveCurrentProfile(name)
                        profileInputModal.visible = false
                        imgui.CloseCurrentPopup()
                    end
                end
            end
            imgui.SameLine()
            if imgui.Button('Cancel', { 80, 0 }) then
                profileInputModal.visible = false
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        if profileConfirmModal.visible then
            imgui.OpenPopup('ProfileConfirm')
        end
        if imgui.BeginPopupModal('ProfileConfirm', nil, ImGuiWindowFlags_AlwaysAutoResize) then
            if profileConfirmModal.action == 'delete' then
                imgui.Text(string.format('Delete profile "%s"? This cannot be undone.', profileConfirmModal.name))
                if imgui.Button('OK', { 80, 0 }) then
                    deleteProfile(profileConfirmModal.name)
                    profileConfirmModal.visible = false
                    imgui.CloseCurrentPopup()
                end
                imgui.SameLine()
                if imgui.Button('Cancel', { 80, 0 }) then
                    profileConfirmModal.visible = false
                    imgui.CloseCurrentPopup()
                end
            end
            imgui.EndPopup()
        end

        -- Packet queue is now processed globally, not just when UI is open

        if imgui.BeginTabBar('##ScentHoundTabBar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            if imgui.BeginTabItem('Active Tracking') then
                if imgui.BeginChild('TrackList', { 0, 340 }, true) then
                    if imgui.BeginTable('TrackTable', 2, bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerV, ImGuiTableFlags_SizingStretchProp)) then
                        imgui.TableSetupColumn('##EntityColumn', ImGuiTableColumnFlags_WidthStretch)
                        imgui.TableSetupColumn('##Action', ImGuiTableColumnFlags_WidthFixed)
                        for index, entry in ipairs(sortedTrack) do
                            imgui.TableNextRow()
                            imgui.TableSetColumnIndex(0)
                            if imgui.Selectable(entry:ToString(), index == trackSelection) then
                                trackSelection = index;
                            end
                            imgui.TableSetColumnIndex(1)
                            local btn_label = string.format('-##untrack_%s', tostring(entry.Id));
                            local btn_width = 28;
                            if imgui.Button(btn_label, { btn_width, imgui.GetTextLineHeightWithSpacing() }) then
                                gPacketList[entry] = nil;
                                gSettings.Monitored[entry.Id] = nil;
                                gUpdate = true;
                                gUpdateTimer = os.clock() + 5;
                                settings.save();
                                RebuildTracking();
                                if trackSelection == index then
                                    trackSelection = -1;
                                end
                            end
                        end
                        imgui.EndTable()
                    end
                    imgui.EndChild();
                end

                local singlePacketActive = (singlePacketQueue ~= nil)

                if not singlePacketActive then
                    if imgui.Button('Single Packet All') then
                        if #sortedTrack > 0 then
                            singlePacketQueue = {}
                            for _, entry in ipairs(sortedTrack) do
                                table.insert(singlePacketQueue, entry)
                            end
                            singlePacketNextSend = os.clock()
                            print(chat.header('ScentHound') .. chat.message('Starting delayed packet send for all tracked mobs.'))
                        end
                    end
                    imgui.SameLine()
                else
                    imgui.TextColored({ 1.0, 0.5, 0.2, 1.0 }, 'Sending...')
                    imgui.SameLine()
                end

                if imgui.Button('Clear') then
                    for index, entry in ipairs(sortedTrack) do
                        gPacketList[entry] = nil;
                        gSettings.Monitored[entry.Id] = nil;
                    end

                    gUpdate = true;
                    gUpdateTimer = os.clock() + 5;
                    settings.save();
                    RebuildTracking();
                    trackSelection = -1;
                end

                if trackSelection ~= -1 then
                    local entry = sortedTrack[trackSelection];
                    if entry then
                        imgui.BeginGroup();
                        if imgui.Checkbox('Alarm##ScentHoundAlarmButton', { entry.Alarm }) then
                            entry.Alarm = not entry.Alarm;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                        imgui.ShowHelp('Play an audible alarm when the monster pops.');
                        if imgui.Checkbox('Draw##ScentHoundDrawButton', { entry.Draw }) then
                            entry.Draw = not entry.Draw;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                        imgui.ShowHelp('Draw an arc to the monster when the monster is alive.');
                        imgui.EndGroup();
                        imgui.SameLine();
                        imgui.BeginGroup();
                        if imgui.Checkbox('Widescan On Pop##ScentHoundWidescanButton', { entry.Widescan }) then
                            entry.Widescan = not entry.Widescan;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                        imgui.ShowHelp('Immediately track monster on widescan when it pops.');
                        if imgui.Button('Single Widescan') then
                            local cmd = string.format('/watchdog track %u', bit.band(entry.Id, 0x7FF));
                            AshitaCore:GetChatManager():QueueCommand(-1, cmd);
                        end
                        imgui.ShowHelp('Attempt to track the monster or NPC on widescan.');
                        imgui.EndGroup();
                        if gSettings.AllowPacketSearch == true then
                            imgui.SameLine();
                            imgui.BeginGroup();
                            local isTracked = gPacketList[entry] ~= nil;
                            if imgui.Checkbox('Repeat Packet##ScentHoundPacketsButton', { isTracked }) then
                                if isTracked then
                                    gPacketList[entry] = nil;
                                else
                                    gPacketList[entry] = 0;
                                end
                            end
                            imgui.ShowHelp('Send periodic 0x16 packets to force server to update monster.');
                            if imgui.Button('Single Packet') then
                                local packet = struct.pack('LL', 0, bit.band(entry.Id, 0x7FF));
                                AshitaCore:GetPacketManager():AddOutgoingPacket(0x16, packet:totable());
                                print(chat.header('ScentHound') .. chat.message(string.format('Sent update request packet for %s.', entry:ToString())));
                            end
                            imgui.ShowHelp('Send one 0x16 packet to force server to update monster.');
                            imgui.EndGroup();
                        end
                        if entry.Draw then
                            local oldColor = entry.Color
                            ColorSelector(entry, 'Color');
                            if entry.Color ~= oldColor then
                                gSettings.EntityColors[entry.Id] = entry.Color
                                settings.save()
                            end
                        end
                        if imgui.Button('Remove##ScentHoundRemoveButton') then
                            gPacketList[entry] = nil;
                            gSettings.Monitored[entry.Id] = nil;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                            settings.save();
                            RebuildTracking();
                            trackSelection = -1;
                        end
                        imgui.ShowHelp('Remove monster from tracking.');
                    end
                end
                imgui.EndTabItem();
            else
                trackSelection = -1
            end

            if imgui.BeginTabItem('Zone List') then
                imgui.Text(string.format('Search (%i)', #searchResults));
                imgui.SetNextItemWidth(-1);
                if imgui.InputText('##ScentHoundSearchInput', searchInput, 48) then
                    gui:UpdateSearch();
                end

                if imgui.Button('Add all') then
                    local added = 0
                    for _, entry in ipairs(searchResults) do
                        if gSettings.Monitored[entry.Id] ~= entry then
                            gSettings.Monitored[entry.Id] = entry
                            added = added + 1
                        end
                    end
                    if added > 0 then
                        gUpdate = true
                        gUpdateTimer = os.clock() + 5
                        settings.save()
                        print(chat.header('ScentHound') .. chat.message(string.format('Added %d mobs to tracking.', added)))
                        RebuildTracking()
                    else
                        print(chat.header('ScentHound') .. chat.error('All mobs in the list are already being tracked.'))
                    end
                end

                if imgui.BeginChild('ZoneList', { 0, 340 }, true) then
                    local clipper = ImGuiListClipper.new();
                    clipper:Begin(#searchResults, -1);
                    while clipper:Step() do
                        if imgui.BeginTable('ZoneTable', 2, bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerV, ImGuiTableFlags_SizingStretchProp)) then
                            imgui.TableSetupColumn('##EntityColumn', ImGuiTableColumnFlags_WidthStretch)
                            imgui.TableSetupColumn('##Action', ImGuiTableColumnFlags_WidthFixed)
                            for i = clipper.DisplayStart, clipper.DisplayEnd - 1 do
                                local entry = searchResults[i + 1];
                                imgui.TableNextRow()
                                imgui.TableSetColumnIndex(0)
                                local selectable_height = imgui.GetTextLineHeightWithSpacing();
                                if imgui.Selectable(entry:ToString(), i + 1 == zoneSelection, 0, { 0, selectable_height }) then
                                    zoneSelection = i + 1;
                                end
                                imgui.TableSetColumnIndex(1)
                                local btn_label = string.format('+##track_%s', tostring(entry.Id));
                                local btn_width = 28;
                                if imgui.Button(btn_label, { btn_width, selectable_height }) then
                                    if gSettings.Monitored[entry.Id] ~= entry then
                                        gSettings.Monitored[entry.Id] = entry;
                                        gUpdate = true;
                                        gUpdateTimer = os.clock() + 5;
                                        settings.save();
                                        print(chat.header('ScentHound') .. chat.message(string.format('%s added to tracking.', entry:ToString())));
                                        RebuildTracking();
                                    else
                                        print(chat.header('ScentHound') .. chat.error(string.format('%s is already being tracked.', entry:ToString())));
                                    end
                                end

                                if imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(0) then
                                    if gSettings.Monitored[entry.Id] ~= entry then
                                        gSettings.Monitored[entry.Id] = entry;
                                        gUpdate = true;
                                        gUpdateTimer = os.clock() + 5;
                                        settings.save();
                                        print(chat.header('ScentHound') .. chat.message(string.format('%s added to tracking.', entry:ToString())));
                                        RebuildTracking();
                                    else
                                        print(chat.header('ScentHound') .. chat.error(string.format('%s is already being tracked.', entry:ToString())));
                                    end
                                end
                            end
                            imgui.EndTable()
                        end
                    end
                    clipper:End();
                    imgui.EndChild();
                end

                if zoneSelection ~= -1 then
                    local entry = searchResults[zoneSelection];
                    local buffer = { entry.Alias };
                    imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Alias');
                    if imgui.InputText(string.format('##ScentHoundAlias', entry.Id), buffer, 256) then
                        entry.Alias = buffer[1];
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                    if imgui.Button('Track') then
                        if gSettings.Monitored[entry.Id] ~= entry then
                            gSettings.Monitored[entry.Id] = entry;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                            settings.save();
                            print(chat.header('ScentHound') .. chat.message(string.format('%s added to tracking.', entry:ToString())));
                            RebuildTracking();
                        else
                            print(chat.header('ScentHound') .. chat.error(string.format('%s is already being tracked.', entry:ToString())));
                        end
                    end
                end
                imgui.EndTabItem();
            end

            if imgui.BeginTabItem('Misc.') then
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Identifier Type');
                if imgui.BeginCombo('##ScentHoundIdType', gSettings.IdentifierType, ImGuiComboFlags_None) then
                    local current = gSettings.IdentifierType;
                    for _, entry in ipairs(identifierOptions) do
                        if imgui.Selectable(entry, entry == current) then
                            gSettings.IdentifierType = entry;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                    end
                end
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Alarm File');
                local buffer = { gSettings.Sound };
                if imgui.InputText('##ScentHoundAlarmFile', buffer, 256) then
                    if buffer[1] ~= gSettings.Sound then
                        gSettings.Sound = buffer[1];
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                end
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Default Color');
                ColorSelector(gSettings, 'DefaultColor');
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Packet Search [DANGEROUS]');
                if imgui.Checkbox('Enabled', { gSettings.AllowPacketSearch }) then
                    gSettings.AllowPacketSearch = not gSettings.AllowPacketSearch;
                    if not gSettings.AllowPacketSearch then
                        gPacketList = {};
                    end
                    --No delay on disabling this saving to disc..
                    settings.save();
                    gUpdate = false;
                end
                imgui.ShowHelp('Allow 0x16 packet searching. This is easily detectable by server and risks a ban if SE becomes more concerned about it.');
                if gSettings.AllowPacketSearch then
                    imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Packet Frequency (Seconds)');
                    local frequency = { gSettings.PacketSearchDelay };
                    if (imgui.SliderFloat('##PacketSearchFrequency', frequency, 0.4, 300, '%.2f', ImGuiSliderFlags_AlwaysClamp)) then
                        if (frequency[1] ~= gSettings.PacketSearchDelay) then
                            gSettings.PacketSearchDelay = math.min(math.max(0.4, frequency[1]), 300);
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                    end
                    imgui.ShowHelp('Set delay between 0x16 packets. With multiple targets being tracked, they will rotate.');
                end
            end
            imgui.EndTabBar();
        end
        imgui.End();
    end
end

return gui;
