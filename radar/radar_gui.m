function radar_gui()
%RADAR_GUI Tower-side radar that shows X-Plane aircraft published over MQTT.
%
%   Usage:
%     >> addpath('radar')
%     >> radar_gui
%
%   Workflow:
%     1. Set broker host/port (default broker.emqx.io:1883), click Connect.
%     2. Subscriptions default to 'radar/aircraft/+/state' (wildcard) — any
%        aircraft publishing under that prefix will be auto-discovered.
%     3. Set tower lat/lon so range/bearing are measured from your reference
%        point. Defaults to a SBSP-area position.
%
%   Aircraft are shown as triangular blips with a fading trail of the last
%   N samples. After 10 s without an update they turn grey (STALE); after
%   60 s they are forgotten.

    % --- Path setup ---
    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(fullfile(repo, 'common'));

    % Kill any leftover redraw timers from previous radar_gui sessions
    % (e.g. when the user used `close all force` instead of the X button,
    % which skips CloseRequestFcn and orphans the timer).
    old_timers = timerfind('Name', 'radar_redraw');
    if ~isempty(old_timers)
        stop(old_timers);
        delete(old_timers);
    end

    % --- Initial state (captured by all nested callbacks via closure) ---
    state = radar_state();

    % Handles to the optional fullscreen view (created lazily on demand)
    fs_fig         = [];
    fs_pax         = [];   % polaraxes (PPI mode) OR axes (Map mode)
    fs_layout      = [];   % parent uigridlayout — needed to rebuild axes
    fs_range_field = [];
    fs_toggle_btn  = [];
    fs_title_lbl   = [];
    fs_mode        = 'ppi';

    % ============================  UI  ============================
    fig = uifigure('Name', 'X-Plane Radar (MQTT)', 'Position', [80 80 1280 780]);
    fig.CloseRequestFcn = @on_close;

    main = uigridlayout(fig, [4 1]);
    main.RowHeight   = {48, 150, '1x', 26};
    main.RowSpacing  = 8;
    main.Padding     = [10 10 10 10];

    % ---- Top: broker config ----
    top = uigridlayout(main, [1 9]);
    top.ColumnWidth = {'fit', 240, 'fit', 80, 110, 16, 'fit', 16, '1x'};
    top.ColumnSpacing = 8;
    uilabel(top, 'Text', 'Broker:');
    brokerField = uieditfield(top, 'text', 'Value', state.broker);
    uilabel(top, 'Text', 'Port:');
    portField = uieditfield(top, 'numeric', 'Value', state.port, ...
                            'Limits', [1 65535], 'ValueDisplayFormat', '%d');
    connectBtn = uibutton(top, 'Text', 'Connect', 'ButtonPushedFcn', @on_connect);
    uilabel(top, 'Text', ' ');
    uilabel(top, 'Text', 'Status:');
    statusDot = uilabel(top, 'Text', char(9679), ...      % big dot
                         'FontColor', [0.6 0.6 0.6], 'FontSize', 22);
    statusLbl = uilabel(top, 'Text', 'disconnected');

    % ---- Subscriptions panel ----
    subsPanel = uigridlayout(main, [2 1]);
    subsPanel.RowHeight = {30, '1x'};
    subsPanel.RowSpacing = 4;

    subRow = uigridlayout(subsPanel, [1 4]);
    subRow.ColumnWidth = {'fit', '1x', 90, 90};
    subRow.ColumnSpacing = 6;
    uilabel(subRow, 'Text', 'Topic:');
    topicField = uieditfield(subRow, 'text', 'Value', 'radar/aircraft/+/state');
    addBtn     = uibutton(subRow, 'Text', 'Subscribe',  'ButtonPushedFcn', @on_add_topic);
    rmBtn      = uibutton(subRow, 'Text', 'Unsubscribe','ButtonPushedFcn', @on_rm_topic);

    subsList = uilistbox(subsPanel, 'Items', state.subscriptions, ...
                        'Multiselect', 'off');

    % ---- Display body: PPI + side panel ----
    body = uigridlayout(main, [1 2]);
    body.ColumnWidth = {'2x', '1x'};
    body.ColumnSpacing = 10;

    % PPI radar
    pax = polaraxes(body);
    pax.ThetaZeroLocation = 'top';
    pax.ThetaDir          = 'clockwise';
    pax.RLim              = [0 state.max_range_km*1000];
    pax.Title.String      = 'PPI Radar';
    pax.GridColor         = [0.3 0.7 0.3];
    pax.GridAlpha         = 0.4;
    pax.Color             = [0.05 0.1 0.05];
    pax.RColor            = [0.6 0.9 0.6];
    pax.ThetaColor        = [0.6 0.9 0.6];
    hold(pax, 'on');

    % Right side panel
    rightSide = uigridlayout(body, [3 1]);
    rightSide.RowHeight = {'1x', 40, 40};
    rightSide.RowSpacing = 6;

    acTable = uitable(rightSide);
    acTable.ColumnName    = {'Callsign','Range (km)','Brg','Alt (m)','Hdg','Status'};
    acTable.ColumnEditable = false(1,6);
    acTable.RowName       = {};
    acTable.Data          = cell(0,6);

    twrRow = uigridlayout(rightSide, [1 6]);
    twrRow.ColumnWidth = {'fit', 90, 90, 'fit', 70, 70};
    twrRow.ColumnSpacing = 6;
    uilabel(twrRow, 'Text', 'Tower lat/lon:');
    twrLat = uieditfield(twrRow, 'numeric', 'Value', state.tower_lat, ...
                         'ValueDisplayFormat', '%.4f');
    twrLon = uieditfield(twrRow, 'numeric', 'Value', state.tower_lon, ...
                         'ValueDisplayFormat', '%.4f');
    uilabel(twrRow, 'Text', 'Range (km):');
    maxRange = uieditfield(twrRow, 'numeric', 'Value', state.max_range_km, ...
                           'Limits', [1 500], ...
                           'ValueChangedFcn', @on_range_change);
    uibutton(twrRow, 'Text', 'Snap', ...
             'Tooltip', 'Pin tower lat/lon to the first known aircraft', ...
             'ButtonPushedFcn', @on_snap_tower);

    trailRow = uigridlayout(rightSide, [1 4]);
    trailRow.ColumnWidth = {'fit', 60, 'fit', 60};
    uilabel(trailRow, 'Text', 'Trail length:');
    trailField = uieditfield(trailRow, 'numeric', 'Value', state.trail_len, ...
                              'Limits', [0 500], ...
                              'ValueChangedFcn', @(s,~) set_trail(s.Value));
    uilabel(trailRow, 'Text', 'Stale (s):');
    staleField = uieditfield(trailRow, 'numeric', 'Value', state.stale_sec, ...
                              'Limits', [1 600], ...
                              'ValueChangedFcn', @(s,~) set_stale(s.Value));

    bottomRow = uigridlayout(main, [1 2]);
    bottomRow.ColumnWidth   = {'1x', 130};
    bottomRow.ColumnSpacing = 8;
    bottomRow.Padding       = [0 0 0 0];
    bottomLbl = uilabel(bottomRow, 'Text', 'idle', 'FontColor', [0.4 0.4 0.4]);
    uibutton(bottomRow, 'Text', 'Open Fullscreen', ...
             'Tooltip', 'Open the PPI in a separate fullscreen window', ...
             'ButtonPushedFcn', @on_fullscreen);

    % ---- Redraw timer (10 Hz) ----
    redrawT = timer('Name', 'radar_redraw', 'Period', 0.1, ...
                    'ExecutionMode', 'fixedRate', 'BusyMode', 'drop', ...
                    'TimerFcn', @(~,~) redraw());
    start(redrawT);

    % ============================  Callbacks  ============================

    function on_connect(~, ~)
        if state.connected
            disconnect();
            return;
        end
        try
            state.broker = strtrim(brokerField.Value);
            state.port   = portField.Value;
            statusLbl.Text = 'connecting...';
            drawnow;
            state.client = mqttclient(state.broker, Port=state.port);
            % Subscribe to whatever is already in the list
            for k = 1:numel(state.subscriptions)
                subscribe(state.client, state.subscriptions{k}, ...
                          Callback=@on_message);
            end
            state.connected     = true;
            state.tower_snapped = false;   % allow auto-snap on next msg
            statusDot.FontColor = [0.2 0.85 0.2];
            statusLbl.Text = 'connected';
            connectBtn.Text = 'Disconnect';
            brokerField.Editable = 'off';
            portField.Editable   = 'off';
        catch ME
            statusDot.FontColor = [0.85 0.2 0.2];
            statusLbl.Text = ['error: ' ME.message];
            state.client = [];
            state.connected = false;
        end
    end

    function disconnect()
        try
            state.client = [];   % mqttclient destructor disconnects
        catch
        end
        state.connected = false;
        statusDot.FontColor = [0.6 0.6 0.6];
        statusLbl.Text = 'disconnected';
        connectBtn.Text = 'Connect';
        brokerField.Editable = 'on';
        portField.Editable   = 'on';
    end

    function on_add_topic(~, ~)
        t = strtrim(topicField.Value);
        if isempty(t), return; end
        if any(strcmp(state.subscriptions, t))
            statusLbl.Text = 'topic already subscribed';
            return;
        end
        state.subscriptions{end+1} = t;
        subsList.Items = state.subscriptions;
        if state.connected
            try
                subscribe(state.client, t, Callback=@on_message);
            catch ME
                statusLbl.Text = ['subscribe error: ' ME.message];
            end
        end
    end

    function on_rm_topic(~, ~)
        sel = subsList.Value;
        if isempty(sel), return; end
        idx = find(strcmp(state.subscriptions, sel), 1);
        if isempty(idx), return; end
        if state.connected
            try
                unsubscribe(state.client, sel);
            catch
            end
        end
        state.subscriptions(idx) = [];
        subsList.Items = state.subscriptions;
    end

    function on_message(topic, data)
        % Industrial Communication Toolbox callback signature: (topic, data).
        % `topic` is a string scalar; `data` is a string (text payload).
        try
            payload = jsondecode(char(data));
        catch
            return;     % bad payload, drop silently
        end
        if ~isfield(payload, 'callsign') || isempty(payload.callsign)
            return;
        end
        cs = char(payload.callsign);
        payload.last_rx = posixtime(datetime('now'));
        payload.topic   = char(string(topic));
        state.aircraft(cs) = payload;

        % Auto-snap tower to the first aircraft seen on this connection
        if ~state.tower_snapped
            state.tower_lat = payload.lat;
            state.tower_lon = payload.lon;
            twrLat.Value    = payload.lat;
            twrLon.Value    = payload.lon;
            state.tower_snapped = true;
            statusLbl.Text = sprintf('tower snapped to %s', cs);
        end

        if isKey(state.history, cs)
            h = state.history(cs);
        else
            h = struct('lat',[],'lon',[],'alt',[]);
        end
        h.lat(end+1) = payload.lat;
        h.lon(end+1) = payload.lon;
        h.alt(end+1) = payload.alt;
        if numel(h.lat) > state.trail_len
            h.lat = h.lat(end-state.trail_len+1:end);
            h.lon = h.lon(end-state.trail_len+1:end);
            h.alt = h.alt(end-state.trail_len+1:end);
        end
        state.history(cs) = h;
    end

    function on_range_change(~, ~)
        set_range(maxRange.Value);
    end

    function set_range(v)
        state.max_range_km = v;
        maxRange.Value     = v;
        pax.RLim           = [0 v*1000];
        if ~isempty(fs_pax) && isvalid(fs_pax)
            if isa(fs_pax, 'matlab.graphics.axis.PolarAxes')
                fs_pax.RLim = [0 v*1000];
            else
                apply_map_limits(fs_pax);
            end
        end
        if ~isempty(fs_range_field) && isvalid(fs_range_field)
            fs_range_field.Value = v;
        end
    end

    function on_snap_tower(~, ~)
        ks = keys(state.aircraft);
        if isempty(ks)
            statusLbl.Text = 'no aircraft to snap to';
            return;
        end
        cs = ks{1};
        ac = state.aircraft(cs);
        state.tower_lat = ac.lat;
        state.tower_lon = ac.lon;
        twrLat.Value = ac.lat;
        twrLon.Value = ac.lon;
        state.tower_snapped = true;
        % Drop history so the trail restarts from the new origin
        if isKey(state.history, cs)
            remove(state.history, cs);
        end
        statusLbl.Text = sprintf('tower snapped to %s', cs);
    end

    function set_trail(v)
        state.trail_len = round(v);
    end

    function set_stale(v)
        state.stale_sec = v;
    end

    function redraw()
        % Bail quietly if the main figure has gone away (e.g. user closed
        % the window or the timer fired during teardown).
        if ~isvalid(fig) || ~isvalid(pax)
            return;
        end
        try
            state.tower_lat = twrLat.Value;
            state.tower_lon = twrLon.Value;

            now_s = posixtime(datetime('now'));
            ks = keys(state.aircraft);
            keep  = cell(0);
            stale = cell(0);
            for k = 1:numel(ks)
                cs = ks{k};
                ac = state.aircraft(cs);
                age = now_s - ac.last_rx;
                if age > state.drop_sec
                    remove(state.aircraft, cs);
                    if isKey(state.history, cs), remove(state.history, cs); end
                    continue;
                end
                keep{end+1} = cs; %#ok<AGROW>
                if age > state.stale_sec
                    stale{end+1} = cs; %#ok<AGROW>
                end
            end

            % Render to the main PPI ...
            render_ppi(pax, keep, stale);
            % ... and to the fullscreen axes if it's open, picking the
            % renderer based on whether the axes is polar or cartesian.
            if ~isempty(fs_pax) && isvalid(fs_pax)
                if isa(fs_pax, 'matlab.graphics.axis.PolarAxes')
                    render_ppi(fs_pax, keep, stale);
                else
                    render_map(fs_pax, keep, stale);
                end
            end

            % Update the aircraft table (only lives in the main window)
            rows = cell(numel(keep), 6);
            for k = 1:numel(keep)
                cs = keep{k};
                ac = state.aircraft(cs);
                [r_m, brg_rad] = ll2rb(state.tower_lat, state.tower_lon, ac.lat, ac.lon);
                isStale = any(strcmp(stale, cs));
                rows{k,1} = cs;
                rows{k,2} = sprintf('%.2f',  r_m/1000);
                rows{k,3} = sprintf('%03d',  round(mod(rad2deg(brg_rad),360)));
                rows{k,4} = sprintf('%.0f',  ac.alt);
                rows{k,5} = sprintf('%.0f',  mod(rad2deg(ac.hdg),360));
                if isStale, rows{k,6} = 'STALE'; else, rows{k,6} = 'OK'; end
            end
            acTable.Data = rows;

            bottomLbl.Text = sprintf('%d aircraft tracked  |  %s', ...
                numel(keep), char(datetime('now','Format','HH:mm:ss')));
        catch ME
            if isvalid(bottomLbl)
                bottomLbl.Text = ['redraw error: ' ME.message];
            end
        end
    end

    function render_ppi(ax, keep, stale)
        % Draw all aircraft blips and trails into one polaraxes.
        cla(ax);
        ax.RTick      = linspace(0, state.max_range_km*1000, 6);
        ax.RTickLabel = arrayfun(@(r) sprintf('%.0f km', r/1000), ...
                                  ax.RTick, 'UniformOutput', false);
        ax.ThetaTick      = 0:30:330;
        ax.ThetaTickLabel = arrayfun(@(t) sprintf('%03d', t), ...
                                      ax.ThetaTick, 'UniformOutput', false);

        for k = 1:numel(keep)
            cs = keep{k};
            ac = state.aircraft(cs);
            [r_m, brg_rad] = ll2rb(state.tower_lat, state.tower_lon, ac.lat, ac.lon);
            isStale = any(strcmp(stale, cs));
            if isStale, color = [0.6 0.6 0.6]; else, color = [0.2 1.0 0.4]; end

            % Trail
            if isKey(state.history, cs)
                h = state.history(cs);
                if numel(h.lat) >= 2
                    [rT, brgT] = ll2rb(state.tower_lat, state.tower_lon, h.lat, h.lon);
                    polarplot(ax, brgT, rT, '-', 'Color', color, 'LineWidth', 1);
                end
            end

            % Blip + label
            polarscatter(ax, brg_rad, r_m, 110, color, 'filled', ...
                         'Marker', '^', 'MarkerEdgeColor', 'w');
            lbl = sprintf('  %s  %.0fm', cs, ac.alt);
            text(ax, brg_rad, r_m, lbl, 'FontSize', 9, ...
                 'Color', color, 'VerticalAlignment','bottom', ...
                 'FontWeight','bold');
        end
    end

    function render_map(ax, keep, stale)
        % Draw all aircraft blips and trails into a cartesian axes
        % (X = East km, Y = North km). Preserve the user's pan/zoom state
        % (XLim/YLim) across redraws.
        xl = ax.XLim;
        yl = ax.YLim;
        delete(ax.Children);

        % Faint range rings centered on tower (every max_range/5 km)
        theta_ring = linspace(0, 2*pi, 100);
        n_rings = 5;
        for k = 1:n_rings
            rk = state.max_range_km * k / n_rings;
            plot(ax, rk*cos(theta_ring), rk*sin(theta_ring), '-', ...
                 'Color', [0.3 0.7 0.3 0.35], 'LineWidth', 0.5, ...
                 'HandleVisibility','off');
        end
        % N-S / E-W crosshair extending to current view limits
        plot(ax, xl, [0 0], '-', 'Color', [0.3 0.7 0.3 0.35], ...
             'HandleVisibility','off');
        plot(ax, [0 0], yl, '-', 'Color', [0.3 0.7 0.3 0.35], ...
             'HandleVisibility','off');
        % Tower marker at origin
        plot(ax, 0, 0, 'p', 'MarkerSize', 14, ...
             'MarkerEdgeColor', [0.6 0.95 0.6], ...
             'MarkerFaceColor', [0.6 0.95 0.6], ...
             'HandleVisibility','off');

        for k = 1:numel(keep)
            cs = keep{k};
            ac = state.aircraft(cs);
            [r_m, brg_rad] = ll2rb(state.tower_lat, state.tower_lon, ac.lat, ac.lon);
            r_km = r_m / 1000;
            x = r_km * sin(brg_rad);   % East (km)
            y = r_km * cos(brg_rad);   % North (km)
            isStale = any(strcmp(stale, cs));
            if isStale, color = [0.6 0.6 0.6]; else, color = [0.2 1.0 0.4]; end

            % Trail
            if isKey(state.history, cs)
                h = state.history(cs);
                if numel(h.lat) >= 2
                    [rT, brgT] = ll2rb(state.tower_lat, state.tower_lon, h.lat, h.lon);
                    plot(ax, (rT/1000) .* sin(brgT), (rT/1000) .* cos(brgT), ...
                         '-', 'Color', color, 'LineWidth', 1);
                end
            end

            % Blip + label
            scatter(ax, x, y, 110, color, 'filled', '^', 'MarkerEdgeColor', 'w');
            text(ax, x, y, sprintf('  %s  %.0fm', cs, ac.alt), ...
                 'FontSize', 10, 'Color', color, ...
                 'VerticalAlignment','bottom', 'FontWeight','bold');
        end

        % Restore the user's pan/zoom
        ax.XLim = xl;
        ax.YLim = yl;
    end

    function on_fullscreen(~, ~)
        if ~isempty(fs_fig) && isvalid(fs_fig)
            figure(fs_fig);     % already open — bring to front
            return;
        end
        fs_fig = uifigure('Name', 'X-Plane Radar — Fullscreen', ...
                          'Color', [0 0 0], ...
                          'WindowState', 'fullscreen');
        fs_fig.CloseRequestFcn = @(~,~) on_fs_close();

        fs_layout = uigridlayout(fs_fig, [2 1]);
        fs_layout.RowHeight   = {44, '1x'};
        fs_layout.RowSpacing  = 2;
        fs_layout.Padding     = [4 4 4 4];
        fs_layout.BackgroundColor = [0 0 0];

        fsTop = uigridlayout(fs_layout, [1 8]);
        fsTop.Layout.Row = 1;
        fsTop.Layout.Column = 1;
        fsTop.ColumnWidth = {110, 80, 80, 110, '1x', 'fit', 100, 110};
        fsTop.ColumnSpacing = 8;
        uibutton(fsTop, 'Text', '< Close', ...
                 'ButtonPushedFcn', @(~,~) on_fs_close());
        uibutton(fsTop, 'Text', 'Zoom +', ...
                 'Tooltip', 'Tighten the range (zoom in)', ...
                 'ButtonPushedFcn', @(~,~) zoom_fs(0.5));
        uibutton(fsTop, 'Text', 'Zoom -', ...
                 'Tooltip', 'Loosen the range (zoom out)', ...
                 'ButtonPushedFcn', @(~,~) zoom_fs(2.0));
        fs_toggle_btn = uibutton(fsTop, 'Text', 'Switch to Map', ...
                 'Tooltip', 'Switch between PPI (polar) and Map (cartesian, pan/zoom) view', ...
                 'ButtonPushedFcn', @(~,~) on_toggle_fs_mode());
        fs_title_lbl = uilabel(fsTop, 'Text', 'X-Plane Radar — PPI', ...
                'FontSize', 20, 'FontColor', [0.6 0.9 0.6], ...
                'HorizontalAlignment', 'center');
        uilabel(fsTop, 'Text', 'Range (km):', 'FontColor', [0.6 0.9 0.6]);
        fs_range_field = uieditfield(fsTop, 'numeric', ...
                                     'Value', state.max_range_km, ...
                                     'Limits', [1 1000], ...
                                     'ValueChangedFcn', @(s,~) set_range(s.Value));
        uibutton(fsTop, 'Text', 'Snap', ...
                 'Tooltip', 'Snap tower to first known aircraft', ...
                 'ButtonPushedFcn', @(~,~) on_snap_tower());

        fs_mode = 'ppi';
        build_fs_axes();
    end

    function build_fs_axes()
        % Build (or rebuild) the fullscreen axes for the current fs_mode.
        if isempty(fs_layout) || ~isvalid(fs_layout), return; end
        if ~isempty(fs_pax) && isvalid(fs_pax)
            delete(fs_pax);
        end
        if strcmp(fs_mode, 'ppi')
            ax = polaraxes(fs_layout);
            ax.Layout.Row    = 2;
            ax.Layout.Column = 1;
            ax.ThetaZeroLocation = 'top';
            ax.ThetaDir          = 'clockwise';
            ax.RLim              = [0 state.max_range_km*1000];
            ax.GridColor         = [0.3 0.7 0.3];
            ax.GridAlpha         = 0.45;
            ax.Color             = [0.03 0.08 0.03];
            ax.RColor            = [0.6 0.95 0.6];
            ax.ThetaColor        = [0.6 0.95 0.6];
            ax.FontSize          = 14;
            hold(ax, 'on');
            if ~isempty(fs_title_lbl) && isvalid(fs_title_lbl)
                fs_title_lbl.Text = 'X-Plane Radar — PPI';
            end
            if ~isempty(fs_toggle_btn) && isvalid(fs_toggle_btn)
                fs_toggle_btn.Text = 'Switch to Map';
            end
        else  % 'map'
            ax = axes('Parent', fs_layout);
            ax.Layout.Row    = 2;
            ax.Layout.Column = 1;
            ax.XLimMode      = 'manual';
            ax.YLimMode      = 'manual';
            ax.DataAspectRatio = [1 1 1];  % 1 km East = 1 km North on screen
            ax.Color         = [0.03 0.08 0.03];
            ax.XColor        = [0.6 0.95 0.6];
            ax.YColor        = [0.6 0.95 0.6];
            ax.GridColor     = [0.3 0.7 0.3];
            ax.GridAlpha     = 0.45;
            ax.FontSize      = 13;
            grid(ax, 'on');
            xlabel(ax, 'East (km)');
            ylabel(ax, 'North (km)');
            hold(ax, 'on');
            % XLim/YLim sized so the visible area fills the window while
            % preserving the 1:1 aspect.
            apply_map_limits(ax);
            % Make the built-in axes toolbar (pan / zoom / restore) visible.
            try
                axtoolbar(ax, {'pan','zoomin','zoomout','restoreview','datacursor'});
                enableDefaultInteractivity(ax);
            catch
            end
            if ~isempty(fs_title_lbl) && isvalid(fs_title_lbl)
                fs_title_lbl.Text = 'X-Plane Radar — Map';
            end
            if ~isempty(fs_toggle_btn) && isvalid(fs_toggle_btn)
                fs_toggle_btn.Text = 'Switch to PPI';
            end
        end
        fs_pax = ax;
    end

    function on_toggle_fs_mode()
        if strcmp(fs_mode, 'ppi')
            fs_mode = 'map';
        else
            fs_mode = 'ppi';
        end
        build_fs_axes();
    end

    function apply_map_limits(ax)
        % Set XLim/YLim for the cartesian Map view so the visible area
        % fills the available cell while keeping a 1:1 km aspect.
        % The Range (km) controls the smaller window dimension.
        if isempty(ax) || ~isvalid(ax), return; end
        if isa(ax, 'matlab.graphics.axis.PolarAxes'), return; end
        r = state.max_range_km;
        ar = 1.0;
        try
            if ~isempty(fs_fig) && isvalid(fs_fig)
                fp = fs_fig.Position;
                % Subtract ~52 px for the top toolbar before computing ratio
                ar = fp(3) / max(1, fp(4) - 52);
                ar = max(0.3, min(5.0, ar));
            end
        catch
        end
        if ar >= 1
            ax.XLim = [-r*ar, r*ar];
            ax.YLim = [-r, r];
        else
            ax.XLim = [-r, r];
            ax.YLim = [-r/ar, r/ar];
        end
    end


    function on_fs_close()
        if ~isempty(fs_fig) && isvalid(fs_fig)
            delete(fs_fig);
        end
        fs_fig         = [];
        fs_pax         = [];
        fs_layout      = [];
        fs_range_field = [];
        fs_toggle_btn  = [];
        fs_title_lbl   = [];
        fs_mode        = 'ppi';
    end

    function zoom_fs(factor)
        if isempty(fs_pax) || ~isvalid(fs_pax), return; end
        new_max = max(1, fs_pax.RLim(2) * factor / 1000);
        set_range(new_max);
    end

    function on_close(~, ~)
        try stop(redrawT); delete(redrawT); catch; end
        try disconnect();                   catch; end
        try on_fs_close();                  catch; end
        delete(fig);
    end
end
