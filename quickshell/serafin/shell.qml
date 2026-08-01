//  Serafín Shell · pulse vectorial (QtQuick.Shapes + MSAA) = domo totalmente liso
//  ~/.config/quickshell/serafin/shell.qml   ·   qs -c serafin

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {

    QtObject {
        id: theme
        property color barBg:   "#141419"
        property color accent:  "#b4befe"
        property color accent2: "#cba6f7"
        property color text:    "#cdd6f4"
        property color textDim: "#7f849c"
        property color island:  Qt.rgba(1, 1, 1, 0.07)

        function load(txt) {
            try {
                var c = JSON.parse(txt);
                if (c.barBg)   barBg   = c.barBg;
                if (c.accent)  accent  = c.accent;
                if (c.accent2) accent2 = c.accent2;
                if (c.text)    text    = c.text;
                if (c.textDim) textDim = c.textDim;
            } catch (e) { console.log("Serafín: colors.json inválido, usando defaults"); }
        }
    }

    FileView {
        id: colorsFile
        path: "/home/arise/.config/quickshell/serafin/colors.json"
        watchChanges: true
        onLoaded: theme.load(colorsFile.text())
        onFileChanged: colorsFile.reload()
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    QtObject {
        id: audio
        readonly property var  sink: Pipewire.defaultAudioSink
        readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0
        readonly property bool muted:  (sink && sink.audio) ? sink.audio.muted  : false
        function setVolume(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v)); }
        function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
        function icon() {
            if (muted || volume <= 0) return "\uf026";
            if (volume < 0.5)         return "\uf027";
            return "\uf028";
        }
    }

    QtObject {
        id: power
        readonly property var  bat: UPower.displayDevice
        readonly property real rawPct: bat ? bat.percentage : 0
        readonly property int  percent: Math.round(rawPct <= 1 ? rawPct * 100 : rawPct)
        readonly property bool charging: bat ? (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged) : false
        property string profile: "balanced"

        function icon() {
            if (charging) return "\uf0e7";
            var p = percent;
            if (p >= 90) return "\uf240";
            if (p >= 62) return "\uf241";
            if (p >= 37) return "\uf242";
            if (p >= 12) return "\uf243";
            return "\uf244";
        }
        function setProfile(p) {
            setProfileProc.command = ["powerprofilesctl", "set", p];
            setProfileProc.running = true;
            profile = p;
        }
    }

    Process {
        id: profileProc
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector { id: profileOut; onStreamFinished: power.profile = profileOut.text.trim() }
    }
    Process { id: setProfileProc }
    Timer { interval: 4000; running: true; repeat: true; onTriggered: profileProc.running = true }

    QtObject {
        id: net
        property bool wifiOn: true
        property string ssid: ""
        property var    list: []

        function refresh()   { wifiRadioProc.running = true; wifiListProc.running = true; }
        function rescan()    { wifiActProc.command = ["nmcli","dev","wifi","rescan"]; wifiActProc.running = true; }
        function toggle()    { wifiActProc.command = ["nmcli","radio","wifi", wifiOn ? "off" : "on"]; wifiActProc.running = true; wifiOn = !wifiOn; }
        function connectTo(s){ wifiActProc.command = ["nmcli","dev","wifi","connect", s]; wifiActProc.running = true; }

        function parseRadio(t) { wifiOn = (t.trim() === "enabled"); }
        function parseList(t) {
            var lines = t.split("
"), seen = {}, out = [], cur = "";
            for (var i = 0; i < lines.length; i++) {
                if (!lines[i]) continue;
                var ln = lines[i].replace(/\\:/g, "\u0001");
                var f = ln.split(":");
                if (f.length < 4) continue;
                var active = (f[0] === "*");
                var sig = parseInt(f[1]) || 0;
                var sec = f[2];
                var ss = f.slice(3).join(":").replace(/\u0001/g, ":");
                if (!ss) continue;
                if (active) cur = ss;
                if (seen[ss] !== undefined) {
                    if (sig > out[seen[ss]].signal) out[seen[ss]].signal = sig;
                    if (active) out[seen[ss]].active = true;
                    continue;
                }
                seen[ss] = out.length;
                out.push({ ssid: ss, signal: sig, secure: (sec !== "" && sec !== "--"), active: active });
            }
            out.sort(function (a, b) { return b.signal - a.signal; });
            net.ssid = cur; net.list = out.slice(0, 6);
        }
    }
    Process { id: wifiListProc; running: true; command: ["nmcli","-t","-f","IN-USE,SIGNAL,SECURITY,SSID","dev","wifi"]; stdout: StdioCollector { id: wifiListOut; onStreamFinished: net.parseList(wifiListOut.text) } }
    Process { id: wifiRadioProc; running: true; command: ["nmcli","-t","radio","wifi"]; stdout: StdioCollector { id: wifiRadioOut; onStreamFinished: net.parseRadio(wifiRadioOut.text) } }
    Process { id: wifiActProc; onExited: net.refresh() }

    QtObject {
        id: bt
        property bool powered: false
        property var  devices: []
        property double lastToggle: 0

        function glyph(icon) {
            if (!icon) return "\uf294";
            if (icon.indexOf("audio") >= 0 || icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0) return "\uf025";
            if (icon.indexOf("keyboard") >= 0) return "\uf11c";
            if (icon.indexOf("phone") >= 0) return "\uf10b";
            return "\uf294";
        }
        function refresh() { btProc.running = true; }
        function toggle()  { lastToggle = Date.now(); btActProc.command = ["bluetoothctl","power", powered ? "off" : "on"]; btActProc.running = true; powered = !powered; }
        function toggleDevice(mac, connected) { btActProc.command = ["bluetoothctl", connected ? "disconnect" : "connect", mac]; btActProc.running = true; }

        function parse(t) {
            var lines = t.split("
"), devs = [];
            for (var i = 0; i < lines.length; i++) {
                var ln = lines[i]; if (!ln) continue;
                if (ln.indexOf("POWER:") === 0) { if (Date.now() - bt.lastToggle > 2500) bt.powered = (ln.substring(6).trim() === "1"); continue; }
                if (ln.indexOf("DEV:") === 0) {
                    var p = ln.substring(4).split("|");
                    if (p.length >= 4) devs.push({ connected: (p[0] === "1"), icon: p[1], mac: p[2], name: p.slice(3).join("|") });
                }
            }
            bt.devices = devs.slice(0, 5);
        }
    }
    Process {
        id: btProc
        running: true
        command: ["sh", "-c", "echo POWER:$(bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 1 || echo 0); bluetoothctl devices 2>/dev/null | awk '{print $2}' | while read -r mac; do [ -z \"$mac\" ] && continue; info=$(bluetoothctl info \"$mac\" 2>/dev/null); echo \"$info\" | grep -q 'Paired: yes' || continue; conn=$(echo \"$info\" | grep -q 'Connected: yes' && echo 1 || echo 0); icon=$(echo \"$info\" | sed -n 's/^[[:space:]]*Icon: //p' | head -n1); name=$(echo \"$info\" | sed -n 's/^[[:space:]]*Name: //p' | head -n1); echo \"DEV:$conn|$icon|$mac|$name\"; done"]
        stdout: StdioCollector { id: btOut; onStreamFinished: bt.parse(btOut.text) }
    }
    Process { id: btActProc; onExited: btRefreshTimer.restart() }
    Timer { id: btRefreshTimer; interval: 1500; repeat: false; onTriggered: bt.refresh() }

    Timer { interval: 12000; running: true; repeat: true; onTriggered: { net.refresh(); bt.refresh(); } }

    QtObject {
        id: ui
        property bool atBottom: false
        property bool overBar:  false
        property string hoveredMod: ""
        property real popoutCenterX: 0
        property bool pinned: false
        property bool booted: false
        property bool overChips: false
        property bool overPopout: false
        property bool wallOpen: false        // el selector de wallpapers está abierto

        readonly property bool anyPopoutOpen: hoveredMod !== ""
        readonly property bool hasWindows: {
            const ws = Hyprland.focusedWorkspace;
            if (!ws) return false;
            const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
            for (let i = 0; i < list.length; i++)
                if (list[i].workspace && list[i].workspace.id === ws.id) return true;
            return false;
        }
               readonly property bool revealed:    pinned || !hasWindows || atBottom || overBar || anyPopoutOpen || wallOpen

        readonly property bool barRevealed: pinned || atBottom || overBar || anyPopoutOpen
        readonly property bool barShown:    booted && revealed
        readonly property bool pulseShown:  booted && revealed

        function appGlyph(cls) {
            const c = (cls || "").toLowerCase();
            if (c.indexOf("firefox") >= 0 || c.indexOf("zen") >= 0) return "\uf269";
            if (c.indexOf("chrom") >= 0 || c.indexOf("brave") >= 0)  return "\uf268";
            if (c.indexOf("code") >= 0 || c.indexOf("codium") >= 0)  return "\ue70c";
            if (c.indexOf("kitty") >= 0 || c.indexOf("term") >= 0 || c.indexOf("alacritty") >= 0 || c.indexOf("foot") >= 0) return "\uf120";
            if (c.indexOf("thunar") >= 0 || c.indexOf("nautilus") >= 0 || c.indexOf("dolphin") >= 0 || c.indexOf("files") >= 0) return "\uf07c";
            if (c.indexOf("spotify") >= 0) return "\uf1bc";
            if (c.indexOf("discord") >= 0) return "\uf392";
            if (c.indexOf("telegram") >= 0) return "\uf2c6";
            if (c.indexOf("mpv") >= 0 || c.indexOf("vlc") >= 0) return "\uf03d";
            if (c.indexOf("steam") >= 0) return "\uf1b6";
            if (c.indexOf("obs") >= 0) return "\uf03d";
            return "\uf2d0";
        }
    }

    Timer { interval: 500; running: true; repeat: false; onTriggered: ui.booted = true }

    // ══════════════════════════════════════════════════════════
    //  BARRA (capa Overlay)
    // ══════════════════════════════════════════════════════════
    PanelWindow {
        id: win
        property int barHeight: 56
        property real barWidthFrac: 0.55
        property int restGap: 30
        readonly property int revealZone: ui.revealed ? (restGap + barHeight + 24) : 6

        anchors.bottom: true; anchors.left: true; anchors.right: true
        implicitHeight: 360
        margins.bottom: 0
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
            Region { item: barPlate; intersection: Intersection.Combine }
            Region {
                intersection: Intersection.Combine
                x: popout.x
                y: popout.y + popout.height * (1 - popout.grow)
                width: popout.width
                height: popout.height * popout.grow
            }
            Region {
                intersection: Intersection.Combine
                x: 0; width: win.width
                y: win.height - win.revealZone
                height: win.revealZone
            }
        }

        Timer { id: closeTimer; interval: 260; onTriggered: { if (!ui.overChips && !ui.overPopout) ui.hoveredMod = ""; } }

        component WedgeMarker: Canvas {
            id: wedge
            property int size: 17
            property color col: theme.accent
            property color orbCol: theme.text
            property real mouthAngle: 0.98
            property real bite: 0.40
            property real orbFrac: 0.70
            property real orbRad: 0.20
            implicitWidth: size
            implicitHeight: size
            onColChanged: requestPaint()
            onOrbColChanged: requestPaint()
            onSizeChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2;
                const r = Math.min(width, height) / 2 - 0.5;
                const mouth = wedge.mouthAngle;
                ctx.beginPath();
                ctx.moveTo(cx - r * wedge.bite, cy);
                ctx.arc(cx, cy, r, mouth, Math.PI * 2 - mouth, false);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, col.a);
                ctx.fill();
                const oR = r * wedge.orbRad;
                const orbX = cx + r * wedge.orbFrac;
                ctx.beginPath();
                ctx.arc(orbX, cy, oR, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(orbCol.r, orbCol.g, orbCol.b, 0.95);
                ctx.fill();
            }
        }

        component AngelLogo: Canvas {
            id: ang
            property int size: 26
            property color col: theme.accent
            implicitWidth: size
            implicitHeight: size
            onColChanged: requestPaint()
            onSizeChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const W = width, H = height, cx = W / 2;
                ctx.fillStyle   = Qt.rgba(col.r, col.g, col.b, col.a);
                ctx.strokeStyle = ctx.fillStyle;
                ctx.lineWidth   = Math.max(1.4, W * 0.06);
                ctx.lineJoin = "round"; ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(cx, H * 0.16, W * 0.15, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(cx - W * 0.08, H * 0.52);
                ctx.quadraticCurveTo(cx - W * 0.46, H * 0.40, cx - W * 0.30, H * 0.74);
                ctx.quadraticCurveTo(cx - W * 0.20, H * 0.60, cx - W * 0.08, H * 0.64);
                ctx.closePath(); ctx.fill();
                ctx.beginPath();
                ctx.moveTo(cx + W * 0.08, H * 0.52);
                ctx.quadraticCurveTo(cx + W * 0.46, H * 0.40, cx + W * 0.30, H * 0.74);
                ctx.quadraticCurveTo(cx + W * 0.20, H * 0.60, cx + W * 0.08, H * 0.64);
                ctx.closePath(); ctx.fill();
                ctx.beginPath();
                ctx.arc(cx, H * 0.40, W * 0.11, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(cx, H * 0.48);
                ctx.quadraticCurveTo(cx + W * 0.03, H * 0.66, cx + W * 0.20, H * 0.88);
                ctx.lineTo(cx - W * 0.20, H * 0.88);
                ctx.quadraticCurveTo(cx - W * 0.03, H * 0.66, cx, H * 0.48);
                ctx.closePath(); ctx.fill();
            }
        }

        component StatusMod: Rectangle {
            id: chip
            property string modName
            property string glyph
            property color glyphColor: theme.text
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 30; implicitHeight: 32
            radius: 15
            color: "transparent"
            readonly property bool active: ui.hoveredMod === chip.modName
            Text {
                anchors.centerIn: parent
                text: chip.glyph
                color: chip.glyphColor
                opacity: chip.active ? 1.0 : 0.9
                scale: chip.active ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                font.family: "Symbols Nerd Font"; font.pixelSize: 15
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (ui.hoveredMod === chip.modName) { ui.hoveredMod = ""; }
                    else { closeTimer.stop(); ui.hoveredMod = chip.modName; ui.popoutCenterX = chip.mapToItem(win.contentItem, chip.width / 2, 0).x; }
                }
            }
        }

        // ══════════ POPOUT CURVO ══════════
        Item {
            id: popout
            property real grow: 0

            readonly property int panelW:
                ui.hoveredMod === "audio"   ? 64  :
                ui.hoveredMod === "wifi"    ? 216 :
                ui.hoveredMod === "bt"      ? 200 :
                ui.hoveredMod === "battery" ? 168 : 176
            readonly property int bodyH:
                ui.hoveredMod === "audio"   ? 150 :
                ui.hoveredMod === "wifi"    ? (40 + Math.max(1, Math.min(net.list.length, 6)) * 29) :
                ui.hoveredMod === "bt"      ? (40 + Math.max(1, Math.min(bt.devices.length, 5)) * 29) :
                ui.hoveredMod === "battery" ? 127 : 140
            readonly property int flare: Math.round(Math.min(20, panelW * 0.2))
            property int neckH: 26
            property int topR: 16
            property int overlap: 18

            width: panelW + 2 * flare
            height: bodyH + neckH

            x: Math.max(barPlate.x, Math.min(barPlate.x + barPlate.width - width, ui.popoutCenterX - width / 2))
            anchors.bottom: barPlate.top
            anchors.bottomMargin: -overlap

            transform: Scale {
                origin.x: popout.width / 2; origin.y: popout.height
                xScale: 0.55 + 0.45 * popout.grow
                yScale: popout.grow
            }
            opacity: Math.min(1, popout.grow * 2.2)
            visible: popout.grow > 0.001

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
                shadowBlur: 0.5
                shadowVerticalOffset: 3
            }

            NumberAnimation { id: growOpen;  target: popout; property: "grow"; to: 1; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.45 }
            NumberAnimation { id: growClose; target: popout; property: "grow"; to: 0; duration: 160; easing.type: Easing.InCubic }
            Connections {
                target: ui
                function onHoveredModChanged() {
                    if (ui.hoveredMod === "") {
                        growOpen.stop(); growClose.restart();
                    } else {
                        growClose.stop();
                        popout.grow = 0.3;
                        growOpen.restart();
                    }
                }
            }

            HoverHandler { onHoveredChanged: { ui.overPopout = hovered; closeTimer.restart(); } }

            function buildPath() {
                const pw = panelW, fl = flare, nh = neckH, rr = topR;
                const ch = height - nh, sw = width, sh = height, lx = fl, rx = fl + pw;
                return "M " + (lx + rr) + " 0"
                     + " L " + (rx - rr) + " 0"
                     + " A " + rr + " " + rr + " 0 0 1 " + rx + " " + rr
                     + " L " + rx + " " + ch
                     + " C " + rx + " " + (ch + nh * 0.55) + " " + (sw - fl * 0.45) + " " + sh + " " + sw + " " + sh
                     + " L 0 " + sh
                     + " C " + (fl * 0.45) + " " + sh + " " + lx + " " + (ch + nh * 0.55) + " " + lx + " " + ch
                     + " L " + lx + " " + rr
                     + " A " + rr + " " + rr + " 0 0 1 " + (lx + rr) + " 0"
                     + " Z";
            }

            Shape {
                anchors.fill: parent
                antialiasing: true
                layer.enabled: true
                layer.samples: 8
                ShapePath {
                    fillColor: theme.barBg
                    strokeWidth: 0
                    PathSvg { path: popout.buildPath() }
                }
            }

            Item {
                anchors.fill: parent
                anchors.topMargin: 13
                anchors.leftMargin: popout.flare + 9
                anchors.rightMargin: popout.flare + 9
                anchors.bottomMargin: popout.neckH + 9

                ColumnLayout {
                    visible: ui.hoveredMod === "audio"
                    anchors.fill: parent
                    spacing: 9
                    Text { text: Math.round(audio.volume * 100) + "%"; color: theme.text; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Rectangle {
                            id: vtrack
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: 11; radius: 6; color: Qt.rgba(1, 1, 1, 0.10)
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; radius: 6; color: theme.accent
                                height: parent.height * audio.volume
                                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: (m) => audio.setVolume(1 - m.y / height)
                                onPositionChanged: (m) => { if (pressed) audio.setVolume(1 - m.y / height); }
                            }
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 36; height: 36; radius: 18
                        color: audio.muted ? theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        Text { anchors.centerIn: parent; text: audio.icon(); color: audio.muted ? "#0b0a08" : theme.text; font.family: "Symbols Nerd Font"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: audio.toggleMute() }
                    }
                }

                ColumnLayout {
                    visible: ui.hoveredMod === "wifi"
                    anchors.fill: parent
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "WI-FI"; color: theme.accent; font.family: "Inter"; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                        Rectangle {
                            width: 34; height: 18; radius: 9
                            color: net.wifiOn ? theme.accent : Qt.rgba(1, 1, 1, 0.12)
                            Rectangle { width: 14; height: 14; radius: 7; color: "#fff"; y: 2; x: net.wifiOn ? 18 : 2; Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: net.toggle() }
                        }
                    }
                    Repeater {
                        model: net.wifiOn ? net.list : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 24; radius: 10
                            color: maw.containsMouse ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                                 : (modelData.active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.10) : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 8
                                Text { text: "\uf1eb"; color: modelData.active ? theme.accent : theme.accent2; opacity: 0.35 + 0.65 * (modelData.signal / 100); font.family: "Symbols Nerd Font"; font.pixelSize: 13 }
                                Text { text: modelData.ssid; color: theme.text; font.family: "Inter"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.secure ? "\uf023" : ""; color: theme.textDim; font.family: "Symbols Nerd Font"; font.pixelSize: 10 }
                                Text { text: modelData.active ? "\uf00c" : ""; color: theme.accent; font.family: "Symbols Nerd Font"; font.pixelSize: 12 }
                            }
                            MouseArea { id: maw; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: net.connectTo(modelData.ssid) }
                        }
                    }
                    Text { visible: net.wifiOn && net.list.length === 0; text: "Buscando redes…"; color: theme.textDim; font.family: "Inter"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    Text { visible: !net.wifiOn; text: "Wi-Fi apagado"; color: theme.textDim; font.family: "Inter"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                }

                ColumnLayout {
                    visible: ui.hoveredMod === "bt"
                    anchors.fill: parent
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "BLUETOOTH"; color: theme.accent; font.family: "Inter"; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                        Rectangle {
                            width: 34; height: 18; radius: 9
                            color: bt.powered ? theme.accent : Qt.rgba(1, 1, 1, 0.12)
                            Rectangle { width: 14; height: 14; radius: 7; color: "#fff"; y: 2; x: bt.powered ? 18 : 2; Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bt.toggle() }
                        }
                    }
                    Repeater {
                        model: bt.powered ? bt.devices : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 24; radius: 10
                            color: mab.containsMouse ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                                 : (modelData.connected ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.10) : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 8
                                Text { text: bt.glyph(modelData.icon); color: modelData.connected ? theme.accent : theme.accent2; font.family: "Symbols Nerd Font"; font.pixelSize: 13 }
                                Text { text: modelData.name; color: theme.text; font.family: "Inter"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.connected ? "\uf00c" : ""; color: theme.accent; font.family: "Symbols Nerd Font"; font.pixelSize: 12 }
                            }
                            MouseArea { id: mab; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bt.toggleDevice(modelData.mac, modelData.connected) }
                        }
                    }
                    Text { visible: bt.powered && bt.devices.length === 0; text: "Sin dispositivos"; color: theme.textDim; font.family: "Inter"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    Text { visible: !bt.powered; text: "Bluetooth apagado"; color: theme.textDim; font.family: "Inter"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                }

                ColumnLayout {
                    id: batCol
                    visible: ui.hoveredMod === "battery"
                    anchors.fill: parent
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "BATERÍA"; color: theme.accent; font.family: "Inter"; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                        Text { text: power.icon(); color: power.charging ? theme.accent : theme.text; font.family: "Symbols Nerd Font"; font.pixelSize: 12 }
                        Text { text: power.percent + "%"; color: theme.text; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                    }
                    Repeater {
                        model: [["Rendimiento", "\uf0e7", "performance"], ["Equilibrado", "\uf042", "balanced"], ["Ahorro", "\uf06c", "power-saver"]]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 24; radius: 10
                            color: modelData[2] === power.profile ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22) : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 9
                                Text { text: modelData[1]; color: theme.accent2; font.family: "Symbols Nerd Font"; font.pixelSize: 13 }
                                Text { text: modelData[0]; color: theme.text; font.family: "Inter"; font.pixelSize: 13; Layout.fillWidth: true }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: power.setProfile(modelData[2]) }
                        }
                    }
                }
            }

            // detector de hover del menú (mismo mecanismo que los chips). Qt.NoButton deja pasar clicks/drag.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: { ui.overPopout = true; closeTimer.stop(); }
                onExited: { ui.overPopout = false; closeTimer.restart(); }
            }
        }

        // ══════════ LA BARRA ══════════
        Rectangle {
            id: barPlate
            width: Math.round(win.width * win.barWidthFrac)
            x: (win.width - width) / 2
            height: win.barHeight
            radius: 22
            color: theme.barBg

            y: ui.barShown ? (win.height - win.restGap - win.barHeight) : win.height
            Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.5)
                shadowBlur: 0.4
                shadowVerticalOffset: 2
            }

            HoverHandler { onHoveredChanged: ui.overBar = hovered }

            RowLayout {
                id: barRow
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10

                AngelLogo {
                    Layout.alignment: Qt.AlignVCenter
                    size: 26
                    col: theme.accent
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ui.pinned = !ui.pinned }
                }

                Item {
                    id: wsIsland
                    Layout.preferredHeight: 34
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: wsRow.implicitWidth + 14
                    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                    readonly property int activeIndex: {
                        const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
                        return Math.max(0, Math.min(4, id - 1));
                    }

                    Rectangle { anchors.fill: parent; radius: 999; color: theme.island }

                    Rectangle {
                        id: activePill
                        property var t: null
                        function refresh() { t = wsRepeater.itemAt(wsIsland.activeIndex); }
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28; radius: 14
                        color: theme.accent
                        x: t ? wsRow.x + t.x : 0
                        width: t ? t.width : 28
                        visible: t !== null
                        Behavior on x     { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                        Component.onCompleted: refresh()
                        Timer { interval: 0; running: true; repeat: false; onTriggered: activePill.refresh() }
                        Connections { target: wsIsland; function onActiveIndexChanged() { activePill.refresh(); } }
                    }

                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 8
                        Repeater {
                            id: wsRepeater
                            model: 5
                            delegate: Item {
                                id: wsCell
                                required property int index
                                readonly property int wsId: index + 1
                                readonly property bool isActive: wsIsland.activeIndex === index
                                readonly property var wins: {
                                    const seen = ({});
                                    const out = [];
                                    const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
                                    for (let i = 0; i < list.length; i++) {
                                        const t = list[i];
                                        if (t.workspace && t.workspace.id === wsId) {
                                            const cls = (t.lastIpcObject ? t.lastIpcObject.class : "") || "";
                                            if (seen[cls]) continue;
                                            seen[cls] = true;
                                            out.push(ui.appGlyph(cls));
                                        }
                                    }
                                    return out.slice(0, 3);
                                }
                                readonly property bool isOccupied: wins.length > 0
                                readonly property bool showMark: isActive || isOccupied

                                implicitWidth: Math.max(30, cellRow.implicitWidth + 16)
                                implicitHeight: 28

                                Row {
                                    id: cellRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Rectangle {
                                        visible: !wsCell.showMark
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8; height: 8; radius: 4
                                        color: wsCell.isActive ? "#0b0a08" : theme.textDim
                                    }
                                    WedgeMarker {
                                        visible: wsCell.showMark
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 17
                                        col: wsCell.isActive ? "#0b0a08" : theme.accent
                                        orbCol: wsCell.isActive ? "#0b0a08" : theme.text
                                    }
                                    Repeater {
                                        model: wsCell.wins
                                        delegate: Text {
                                            required property string modelData
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData
                                            color: wsCell.isActive ? "#0b0a08" : theme.text
                                            font.family: "Symbols Nerd Font"; font.pixelSize: 14
                                        }
                                    }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Hyprland.dispatch("workspace " + wsCell.wsId) }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 32
                    Layout.leftMargin: 6; Layout.rightMargin: 6
                    radius: 16
                    color: theme.island
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                        Text { text: "\uf002"; color: theme.textDim; font.family: "Symbols Nerd Font"; font.pixelSize: 13 }
                        Text { text: "Buscar aplicaciones…"; color: theme.textDim; font.family: "Inter"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 36
                    implicitWidth: clockRow.implicitWidth + 20
                    radius: 18
                    color: theme.island
                    RowLayout {
                        id: clockRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: "\uf073"; color: theme.accent2; font.family: "Symbols Nerd Font"; font.pixelSize: 14 }
                        Text { id: clockText; text: "--:--"; color: theme.text; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.bold: true }
                    }
                }

                Rectangle {
                    id: stCluster
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 36
                    implicitWidth: stRow.implicitWidth + 10
                    radius: 18
                    color: theme.island

                    function hoverAt(mx) {
                        ui.overChips = true;
                        closeTimer.stop();
                        var rx = mx - stRow.x;
                        for (var i = 0; i < stRow.children.length; i++) {
                            var c = stRow.children[i];
                            if (!c || c.modName === undefined) continue;
                            if (rx >= c.x && rx <= c.x + c.width) {
                                if (ui.hoveredMod !== c.modName) {
                                    ui.hoveredMod = c.modName;
                                    ui.popoutCenterX = c.mapToItem(win.contentItem, c.width / 2, 0).x;
                                }
                                return;
                            }
                        }
                    }

                    RowLayout {
                        id: stRow
                        anchors.centerIn: parent
                        spacing: 1
                        StatusMod { modName: "wifi"; glyph: "\uf1eb"; glyphColor: (net.wifiOn && net.ssid !== "") ? theme.text : theme.textDim }
                        StatusMod { modName: "bt";   glyph: "\uf294"; glyphColor: bt.powered ? theme.text : theme.textDim }
                        StatusMod {
                            modName: "audio"
                            glyph: audio.icon()
                            glyphColor: audio.muted ? theme.textDim : theme.text
                            WheelHandler { onWheel: (event) => audio.setVolume(audio.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05)) }
                        }
                        StatusMod { modName: "battery"; glyph: power.icon(); glyphColor: power.charging ? theme.accent : theme.text }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: stCluster.hoverAt(mouseX)
                        onPositionChanged: (m) => stCluster.hoverAt(m.x)
                        onExited: { ui.overChips = false; closeTimer.restart(); }
                    }
                }
            }
        }

        Item {
            id: revealStrip
            z: -1
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: win.revealZone
            HoverHandler { onHoveredChanged: ui.atBottom = hovered }
        }

        Timer {
            interval: 1000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: {
                const d = new Date();
                let h = d.getHours();
                const ap = h >= 12 ? "PM" : "AM";
                h = h % 12; if (h === 0) h = 12;
                const m = d.getMinutes().toString().padStart(2, "0");
                clockText.text = (h < 10 ? "0" + h : h) + ":" + m + " " + ap;
            }
        }
    }
            // ══════════════════════════════════════════════════════════
    //  SELECTOR DE WALLPAPERS (paralelogramos) · overlay
    // ══════════════════════════════════════════════════════════
    Wallpapers {
        id: wallpaperPicker
        accent:  theme.accent
        accent2: theme.accent2
        barBg:   theme.barBg
        textCol: theme.text
        textDim: theme.textDim
    }

        Connections {
        target: wallpaperPicker
        function onShownChanged() { ui.wallOpen = wallpaperPicker.shown; }
    }


    // IPC: el keybind (SUPER+SHIFT+W) abre/cierra el selector
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { wallpaperPicker.toggle(); }
        function open(): void  { wallpaperPicker.open(); }
        function close(): void { wallpaperPicker.close(); }
    }

    // ══════════════════════════════════════════════════════════
    //  PULSE (capa Top) · domo liso + sincronizado con la barra
    // ══════════════════════════════════════════════════════════
    PanelWindow {
        id: pulseWin

        anchors { bottom: true; left: true; right: true }
        implicitHeight: 340
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        property real domePeek:     70
        property real visHalfFrac:  0.92
        property real maxBarHeight: 180
        property int  stepPx:       4
        property real level:        1.0
        property real punch:        1.6
        property real bassBoost:    1.9
        property real bassSpan:     0.30

        property real centerVal:    0.32
        property real midVal:       1.40
        property real edgeVal:      1.70
        property real peakAt:       0.50
        property real edgeFadeFrom: 0.85
        property real nopulseFrom:  0.92

        property real lean:         0.12

        property real attack:       0.85
        property real decay:        0.32

        property real  bodyAlpha: 0.72
        property color bodyColor: Qt.rgba(theme.barBg.r, theme.barBg.g, theme.barBg.b, bodyAlpha)
        property color edgeColor: Qt.rgba((theme.accent.r + theme.accent2.r) / 2,
                                          (theme.accent.g + theme.accent2.g) / 2,
                                          (theme.accent.b + theme.accent2.b) / 2, 1.0)
        property real  edgeWidth: 1.5

        property string bodyPath: ""
        property string edgePath: ""

        property var st: ({})

        function mulberry32(s) {
            return function () {
                s |= 0; s = (s + 0x6D2B79F5) | 0;
                var t = Math.imul(s ^ (s >>> 15), 1 | s);
                t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            };
        }
        function smooth(t) { t = Math.max(0, Math.min(1, t)); return t * t * (3 - 2 * t); }

        function envelope(norm) {
            if (norm >= nopulseFrom) return 0;
            var ew;
            if (norm <= peakAt) ew = centerVal + (midVal - centerVal) * smooth(norm / peakAt);
            else                ew = midVal + (edgeVal - midVal) * smooth((norm - peakAt) / (1 - peakAt));
            if (norm > edgeFadeFrom) ew *= 1 - (norm - edgeFadeFrom) / (nopulseFrom - edgeFadeFrom);
            return Math.max(0, ew);
        }

        function initState() {
            st.cava = []; st.cavaAlive = false; st.lastCava = 0; st.t = 0;
            var rnd = mulberry32(99);
            st.bF = []; st.bP = []; st.bA = [];
            for (var i = 0; i < 1200; i++) { st.bF[i] = 2 + rnd() * 8; st.bP[i] = rnd() * 7; st.bA[i] = 0.55 + rnd() * 0.45; }
        }

        function layout() {
            var W = pulseWin.width, H = pulseWin.height;
            if (W <= 0 || H <= 0) return;
            st.W = W; st.H = H;
            st.cols = Math.ceil(W / stepPx);
            st.centerCol = (st.cols - 1) / 2;

            var bandMin = 2, bandMax = 6;
            var rnd = mulberry32(2024);
            var edges = [0], d = 0;
            while (d < st.centerCol + bandMax) { d += bandMin + Math.floor(rnd() * (bandMax - bandMin + 1)); edges.push(d); }
            st.numBands = edges.length - 1;
            st.bCenters = [];
            for (var b = 0; b < st.numBands; b++) st.bCenters[b] = (edges[b] + edges[b + 1]) / 2;
            st.band = new Array(st.numBands).fill(0);
            st.curB = new Array(st.numBands).fill(0);

            st.colK = []; st.colFr = [];
            for (var i = 0; i < st.cols; i++) {
                var dCol = Math.abs(i - st.centerCol);
                var k = 0;
                while (k < st.numBands - 1 && st.bCenters[k + 1] <= dCol) k++;
                var hi = Math.min(k + 1, st.numBands - 1);
                var fr = hi > k ? (dCol - st.bCenters[k]) / (st.bCenters[hi] - st.bCenters[k]) : 0;
                fr = Math.max(0, Math.min(1, fr)); fr = fr * fr * (3 - 2 * fr);
                st.colK[i] = k; st.colFr[i] = fr;
            }

            var r2 = mulberry32(4242);
            var terr = [];
            for (var b = 0; b < st.numBands; b++) terr[b] = 0.45 + 0.7 * Math.pow(r2(), 1.4);
            var tt = terr.slice();
            for (var b = 1; b < st.numBands - 1; b++) terr[b] = tt[b - 1] * 0.25 + tt[b] * 0.5 + tt[b + 1] * 0.25;
            st.colTerr = [];
            for (var i = 0; i < st.cols; i++) {
                var k = st.colK[i], hi = Math.min(k + 1, st.numBands - 1), fr = st.colFr[i];
                st.colTerr[i] = terr[k] * (1 - fr) + terr[hi] * fr;
            }

            st.cx = W / 2;
            var dCross = visHalfFrac * (W / 2);
            st.R = (dCross * dCross + domePeek * domePeek) / (2 * domePeek);
            st.cy = (H - domePeek) + st.R;

            buildPoints();
        }

        function baseY(x) {
            var d = x - st.cx, s = st.R * st.R - d * d;
            return s <= 0 ? st.H + 9999 : st.cy - Math.sqrt(s);
        }

        function setCava(line) {
            if (!line || line.length < 3) return;
            var parts = line.split(";");
            var vals = [];
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] === "") continue;
                vals.push(Math.min(1, parseFloat(parts[i]) / 1000));
            }
            if (vals.length > 0) { st.cava = vals; st.cavaAlive = true; st.lastCava = Date.now(); }
        }

        function updateBands() {
            var nb = st.numBands; if (!nb) return;
            if (st.cavaAlive && st.cava && st.cava.length) {
                var cn = st.cava.length;
                for (var b = 0; b < nb; b++) {
                    var idx = Math.min(cn - 1, Math.floor(b / nb * cn));
                    var val = Math.pow(st.cava[idx], punch);
                    var bt = idx / (cn * bassSpan);
                    var g = bt < 1 ? 1 + (bassBoost - 1) * (1 - bt) : 1;
                    st.band[b] = val * g;
                }
            } else {
                st.t += 0.04;
                var kick = Math.pow(Math.max(0, Math.sin(st.t * 2.2)), 5);
                for (var b = 0; b < nb; b++) {
                    var o = 0.5 + 0.5 * Math.sin(st.t * st.bF[b] + st.bP[b]);
                    st.band[b] = Math.min(1, Math.pow(o, 1.8) * st.bA[b] + kick * 0.22);
                }
            }
            for (var b = 0; b < nb; b++) {
                var diff = st.band[b] - st.curB[b];
                st.curB[b] += diff * (diff > 0 ? attack : decay);
            }
        }

        function buildPoints() {
            var nb = st.numBands; if (!nb) { bodyPath = ""; edgePath = ""; return; }
            var cols = st.cols, W = st.W, H = st.H, cx = st.cx;
            var xt = [], ys = [], vis = [];
            var firstIdx = -1, lastIdx = -1;
            for (var i = 0; i < cols; i++) {
                var k = st.colK[i], hi = Math.min(k + 1, nb - 1), fr = st.colFr[i];
                var v = st.curB[k] * (1 - fr) + st.curB[hi] * fr;
                var xc = i * stepPx + stepPx / 2;
                var by = baseY(xc);
                var norm = Math.abs(xc - cx) / (W / 2);
                var barH = v * st.colTerr[i] * maxBarHeight * envelope(norm) * level;
                xt[i] = xc + lean * barH * (xc < cx ? -1 : 1);
                ys[i] = by - barH;
                vis[i] = (by <= H + 0.5);
                if (vis[i]) { if (firstIdx < 0) firstIdx = i; lastIdx = i; }
            }
            if (firstIdx < 0) { bodyPath = ""; edgePath = ""; return; }

            var floorY = (H + 40).toFixed(1);
            var xStart = (firstIdx * stepPx + stepPx / 2).toFixed(1);
            var xEnd   = (lastIdx  * stepPx + stepPx / 2).toFixed(1);
            var bd = "M " + xStart + " " + floorY;
            var ed = "", edStarted = false;
            for (var i = firstIdx; i <= lastIdx; i++) {
                if (!vis[i]) continue;
                bd += " L " + xt[i].toFixed(1) + " " + ys[i].toFixed(1);
                if (ys[i] <= H - 2) {
                    if (!edStarted) { ed = "M " + xt[i].toFixed(1) + " " + ys[i].toFixed(1); edStarted = true; }
                    else            ed += " L " + xt[i].toFixed(1) + " " + ys[i].toFixed(1);
                }
            }
            bd += " L " + xEnd + " " + floorY + " Z";
            bodyPath = bd;
            edgePath = ed;
        }

        Process {
            id: cavaProc
            running: true
            command: ["sh", "-c", "exec cava -p ~/.config/quickshell/serafin/cava.conf"]
            stdout: SplitParser { onRead: line => pulseWin.setCava(line) }
        }

        Timer {
            interval: 600; running: true; repeat: true
            onTriggered: if (Date.now() - (pulseWin.st.lastCava || 0) > 700) pulseWin.st.cavaAlive = false
        }

        Shape {
            id: viz
            width: parent.width
            height: parent.height
            visible: ui.booted
            y: ui.pulseShown ? 0 : height
            Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

            antialiasing: true
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true

            ShapePath {
                fillColor: pulseWin.bodyColor
                strokeColor: "transparent"
                strokeWidth: 0
                fillRule: ShapePath.WindingFill
                PathSvg { path: pulseWin.bodyPath }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: pulseWin.edgeColor
                strokeWidth: pulseWin.edgeWidth
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: pulseWin.edgePath }
            }
        }

        Timer {
            interval: 33; running: ui.pulseShown; repeat: true
            onTriggered: { pulseWin.updateBands(); pulseWin.buildPoints(); }
        }

        onWidthChanged: layout()
        onHeightChanged: layout()
        Component.onCompleted: { initState(); layout(); }

        Connections {
            target: ui
            function onBootedChanged() { if (ui.booted) pulseWin.layout(); }
        }
    }


}
