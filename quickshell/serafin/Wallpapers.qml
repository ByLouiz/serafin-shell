//  Serafín · selector de wallpapers · COVERFLOW CONTINUO con paralelogramos
//  · una posición virtual (pos) sigue al ratón suavemente; el tamaño se interpola
//    según la cercanía al centro → siempre centrado, fluido, estable.
//  · click = aplicar el centrado.  Se abre con: qs -c serafin ipc call wallpaper toggle

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ── colores (los pasa shell.qml) ──
    property color accent:  "#b4befe"
    property color accent2: "#cba6f7"
    property color barBg:   "#141419"
    property color textCol: "#cdd6f4"
    property color textDim: "#7f849c"

    // ── knobs del look ──
    property real heightFrac: 0.50                        // alto de la tira (tamaño general)
    property int  tileH:      Math.round(height * heightFrac)
    property int  wideW:      Math.round(tileH * 16 / 9)  // ancho del seleccionado (16:9)
    property int  sliverW:    92                          // ancho de las rebanadas
    property real shear:      0.34                        // inclinación (a TODOS)
    property int  gap:        8

    // ── estado ──
    property bool shown: false
    property bool snap: true            // true = sin animación (abrir/centrar al instante)
    property real pos: 0                // posición virtual (0..count-1), la sigue el ratón
    property string currentWall: ""
    readonly property int count: listModel.count

    function toggle() { if (shown) close(); else open(); }
    function open()   { snap = true; listModel.clear(); curProc.running = true; thumbsProc.running = true; shown = true; }
    function close()  { shown = false; }
    function selectCurrent() {
        if (!currentWall) return;
        for (var i = 0; i < listModel.count; i++)
            if (listModel.get(i).orig === currentWall) { snap = true; pos = i; return; }
    }
    // ancho de la pieza i según su cercanía a pos (1 en el centro → wideW; lejos → sliverW)
    function wOf(i) { var t = Math.max(0, 1 - Math.abs(i - pos)); return sliverW + (wideW - sliverW) * t; }
    // coordenada (en la fila) del punto focal = donde debe quedar el centro de la pantalla
    function focalX() {
        var f = Math.floor(pos), frac = pos - f, x = 0;
        for (var i = 0; i < f; i++) x += wOf(i) + gap;
        var cF = x + wOf(f) / 2;
        if (f + 1 >= count) return cF;
        var cF1 = x + wOf(f) + gap + wOf(f + 1) / 2;
        return cF + frac * (cF1 - cF);
    }
    function applyIndex(i) {
        var it = listModel.get(i);
        if (!it) return;
        applyProc.command = ["/home/arise/.local/bin/serafin-wall", it.orig];
        applyProc.running = true;
        close();
    }

    Behavior on pos { enabled: !root.snap; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    // capa Top → queda DEBAJO de la barra (Overlay) y del pulse → esos se ven nítidos encima
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: root.shown ? backdrop : null }

    ListModel { id: listModel }

    Process {
        id: curProc
        command: ["readlink", "-f", "/home/arise/.config/serafin/current-wallpaper"]
        stdout: StdioCollector { id: curOut; onStreamFinished: { root.currentWall = curOut.text.trim(); root.selectCurrent(); } }
    }
    Process {
        id: thumbsProc
        command: ["bash", "/home/arise/.local/bin/serafin-thumbs"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.split("\t");
                if (p.length >= 2 && p[0] && p[1]) {
                    listModel.append({ thumb: "file://" + p[0], orig: p[1], isImg: (p[2] === "img") });
                    if (p[1] === root.currentWall) { root.snap = true; root.pos = listModel.count - 1; }
                }
            }
        }
    }
    Process { id: applyProc }

    // ── fondo oscurecido UNIFORME (barra y pulse quedan encima, nítidos) ──
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: root.shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // teclado
    Item {
        anchors.fill: parent
        focus: root.shown
        Keys.onEscapePressed: root.close()
        Keys.onLeftPressed:  { root.snap = false; root.pos = Math.max(0, Math.round(root.pos) - 1); }
        Keys.onRightPressed: { root.snap = false; root.pos = Math.min(root.count - 1, Math.round(root.pos) + 1); }
        Keys.onReturnPressed: root.applyIndex(Math.round(root.pos))
    }

    // ── coverflow ──
    Item {
        id: panel
        anchors.left: parent.left; anchors.right: parent.right
        height: root.tileH
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.shown ? (parent.height / 2 - height / 2) : (parent.height / 2 - height / 2 + 60)
        opacity: root.shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on y       { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            id: row
            height: parent.height
            spacing: root.gap
            x: panel.width / 2 - root.focalX()      // centra la posición virtual en la pantalla

            Repeater {
                model: listModel
                delegate: Item {
                    id: cell
                    required property int index
                    required property string thumb
                    required property string orig
                    required property bool isImg
                    readonly property real t: Math.max(0, 1 - Math.abs(index - root.pos))
                    readonly property bool sel: Math.round(root.pos) === index

                    width: root.wOf(index)
                    height: row.height
                    z: sel ? 20 : 1

                    // paralelogramo (cizalla en X) · el centro crece un extra
                    Item {
                        anchors.fill: parent
                        scale: 1.0 + 0.15 * cell.t
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, -root.shear, 0,  root.shear * cell.height / 2,
                                                 0,  1,           0,  0,
                                                 0,  0,           1,  0,
                                                 0,  0,           0,  1)
                        }

                        // recorte RECTO (calza con el borde → la imagen no se sale)
                        Rectangle {
                            anchors.fill: parent
                            clip: true
                            color: root.barBg
                            Image {
                                anchors.fill: parent
                                source: cell.thumb                 // SIEMPRE la miniatura → no recarga al seleccionar (sin salto)
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 1280             // tamaño FIJO → tampoco recarga al crecer
                                asynchronous: true
                                cache: true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: cell.sel ? 3 : 1
                            border.color: cell.sel ? root.accent : Qt.rgba(1, 1, 1, 0.18)
                        }
                        Rectangle {   // oscurece según lejanía al centro → profundidad
                            anchors.fill: parent
                            color: "black"
                            opacity: (1 - cell.t) * 0.45
                        }
                    }
                }
            }
        }

        // ── navegación: el ratón mueve la posición virtual · click = aplicar ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => {
                root.snap = false;
                if (root.count <= 1) return;
                var lo = width * 0.08, hi = width * 0.92;     // margen: no hay que llegar al borde exacto
                var f = (m.x - lo) / (hi - lo);
                f = Math.max(0, Math.min(1, f));
                root.pos = f * (root.count - 1);
            }
            onClicked: root.applyIndex(Math.round(root.pos))
        }
    }
}
