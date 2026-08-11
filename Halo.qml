//  Serafín · Halo — menú radial (launcher) sobre el domo.
//  Se abre con:  qs -c serafin ipc call halo toggle

import QtQuick
import QtQuick.Shapes
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    property color accent:  "#ff9c3a"
    property color accent2: "#ffd27a"
    property color barBg:   "#141419"
    property color textCol: "#e7e2d5"

    property var appFavorites: []

    property bool shown: false
    property real uiScale: Math.min(width, height) / 760 * 0.82

    signal requestWallpaper()
    signal requestWallpaperRandom()
    signal requestAppsLauncher()

    function toggle() { if (shown) close(); else open(); }
    function open()  { cv.reset(); shown = true; }
    function close() { shown = false; }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: root.shown ? backdrop : null }

    property real cpuUsage: 0.15
    property real memUsed: 6.8
    property real memTotal: 16.0
    property real diskUsedPct: 0.53
    property real diskFreeGB: 223.0
    property real netRxSpeed: 1.8
    property real netTxSpeed: 0.3

    // Actualizador en vivo de datos de sistema para los widgets laterales
    Timer {
        interval: 1500; running: root.shown; repeat: true
        onTriggered: {
            sysProc.running = true;
        }
    }
    Process {
        id: sysProc
        command: ["sh", "-c", "export LC_ALL=C; top -bn2 -d 0.2 | grep 'Cpu(s)' | tail -n1 | awk '{print 100-$8}'; free -m | awk '/Mem:/ {print $3/1024\" \"$2/1024}'; df -BG / | awk 'NR==2 {print $3/$2\" \"$4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var txt = text.trim();
                var lines = txt.split("\n");
                if (lines.length >= 1) {
                    var cpu = parseFloat(lines[0]);
                    if (!isNaN(cpu) && cpu > 0) root.cpuUsage = Math.min(1.0, Math.max(0.01, cpu / 100.0));
                }
                if (lines.length >= 2) {
                    var m = lines[1].split(" ");
                    if (m.length >= 2) {
                        var u = parseFloat(m[0]), t = parseFloat(m[1]);
                        if (!isNaN(u) && !isNaN(t)) { root.memUsed = u; root.memTotal = t; }
                    }
                }
                if (lines.length >= 3) {
                    var d = lines[2].split(" ");
                    if (d.length >= 2) {
                        var pct = parseFloat(d[0]), freeG = parseFloat(d[1]);
                        if (!isNaN(pct)) root.diskUsedPct = Math.min(1.0, Math.max(0.0, pct));
                        if (!isNaN(freeG)) root.diskFreeGB = freeG;
                    }
                }
            }
        }
    }

    // Componente Gauge en Canvas 2D vectorial ultra-nítido
    component GaugeArc: Canvas {
        id: gaugeCanvas
        width: 120; height: 120
        property real progress: 0.0 // 0.0 a 1.0
        property color trackColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        property color strokeColor: root.accent

        antialiasing: true
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate

        onProgressChanged: requestPaint()
        onStrokeColorChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var cx = width / 2, cy = height / 2, r = 52;
            var start = 129 * Math.PI / 180;
            var total = 280 * Math.PI / 180;
            var endFull = start + total;
            var endVal = start + Math.min(1.0, Math.max(0.001, progress)) * total;

            // Track fondo
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, endFull, false);
            ctx.strokeStyle = trackColor;
            ctx.lineWidth = 9;
            ctx.lineCap = "round";
            ctx.stroke();
            ctx.restore();

            // Valor actual
            if (progress > 0.001) {
                ctx.save();
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, endVal, false);
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = 9;
                ctx.lineCap = "round";
                ctx.stroke();
                ctx.restore();
            }
        }
    }

    // Selector de archivos para cambiar avatar
    FileDialog {
        id: avatarPicker
        title: "Seleccionar foto de perfil"
        nameFilters: ["Imágenes (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            if (selectedFile) {
                copyAvatarProc.command = ["cp", selectedFile.toString().replace("file://", ""), "/home/arise/.config/serafin/avatar.png"];
                copyAvatarProc.running = true;
            }
        }
    }
    Process {
        id: copyAvatarProc
        onExited: {
            var old = avatarImg.source;
            avatarImg.source = "";
            avatarImg.source = old;
        }
    }

    // Ejecutor universal para lanzar comandos/acciones
    Process { id: execProc }

    Process {
        id: cavaProc
        running: root.shown
        command: ["sh", "-c", "exec cava -p ~/.config/quickshell/serafin/cava.conf"]
        stdout: SplitParser { onRead: line => cv.setCava(line) }
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: root.shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Item {
        anchors.fill: parent
        focus: root.shown
        Keys.onEscapePressed: root.close()
    }

    Item {
        id: mainContainer
        anchors.fill: parent

        // Widgets flotantes (PC)
        Item {
            id: widgetsOverlay
            anchors.fill: parent
            scale: (root.shown && cv.subExpandSeg === 3 && cv.subExpandP > 0.15 && cv.introMenu > 0.3) ? root.uiScale : root.uiScale * 0.9
            opacity: (root.shown && cv.subExpandSeg === 3 && cv.subExpandP > 0.15 && cv.introMenu > 0.3) ? 1 : 0
            visible: opacity > 0.01
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Panel Izquierdo (CPU + RAM)
            Rectangle {
                width: 248; height: 320
                radius: 36
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width / 2 - 545
                color: Qt.rgba(0.08, 0.08, 0.06, 0.94)
                border.width: 1.5
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

                Rectangle {
                    width: 48; height: 5; radius: 3
                    anchors.top: parent.top; anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 24

                    Row {
                        spacing: 12
                        Item {
                            width: 120; height: 120
                            GaugeArc {
                                anchors.fill: parent
                                progress: root.cpuUsage
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: Math.round(root.cpuUsage * 100) + "%"; font.pixelSize: 22; font.bold: true; color: "#f4efe2"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: "CPU"; font.pixelSize: 9; color: "#9a9488"; font.letterSpacing: 1.5; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Intel UHD"; font.pixelSize: 13; font.bold: true; color: root.accent }
                            Text { text: "System"; font.pixelSize: 9; color: "#8a8478" }
                        }
                    }

                    Row {
                        spacing: 12
                        Item {
                            width: 120; height: 120
                            GaugeArc {
                                anchors.fill: parent
                                progress: root.memTotal > 0 ? (root.memUsed / root.memTotal) : 0.4
                            }
                            Column {
                                anchors.centerIn: parent
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text { text: root.memUsed.toFixed(1); font.pixelSize: 18; font.bold: true; color: "#f4efe2" }
                                    Text { text: "GB"; font.pixelSize: 11; font.bold: true; color: "#cfc9bd"; anchors.bottom: parent.bottom; anchors.bottomMargin: 2 }
                                }
                                Text { text: "RAM"; font.pixelSize: 9; color: "#9a9488"; font.letterSpacing: 1.5; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: root.memTotal.toFixed(0) + " GB"; font.pixelSize: 13; font.bold: true; color: root.accent }
                            Text { text: "total"; font.pixelSize: 9; color: "#8a8478" }
                        }
                    }
                }
            }

            // Panel Derecho (Disco + Red)
            Rectangle {
                width: 248; height: 320
                radius: 36
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width / 2 + 545 - 248
                color: Qt.rgba(0.08, 0.08, 0.06, 0.94)
                border.width: 1.5
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

                Rectangle {
                    width: 48; height: 5; radius: 3
                    anchors.top: parent.top; anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 24

                    Row {
                        spacing: 12
                        Item {
                            width: 120; height: 120
                            GaugeArc {
                                anchors.fill: parent
                                progress: root.diskUsedPct
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: Math.round(root.diskUsedPct * 100) + "%"; font.pixelSize: 22; font.bold: true; color: "#f4efe2"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: "DISCO"; font.pixelSize: 9; color: "#9a9488"; font.letterSpacing: 1.5; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: root.diskFreeGB.toFixed(0) + " GB"; font.pixelSize: 13; font.bold: true; color: root.accent }
                            Text { text: "libres"; font.pixelSize: 9; color: "#8a8478" }
                        }
                    }

                    Row {
                        spacing: 12
                        Item {
                            width: 120; height: 120
                            GaugeArc {
                                anchors.fill: parent
                                progress: 0.21
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: root.netRxSpeed.toFixed(1); font.pixelSize: 22; font.bold: true; color: "#f4efe2"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: "RED MB/s"; font.pixelSize: 9; color: "#9a9488"; font.letterSpacing: 1.5; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "↑ " + root.netTxSpeed.toFixed(1); font.pixelSize: 13; font.bold: true; color: root.accent }
                            Text { text: "Wi-Fi"; font.pixelSize: 9; color: "#8a8478" }
                        }
                    }
                }
            }
        }

        // Halo Central
        Item {
            id: stage
            anchors.centerIn: parent
            width: 760; height: 760
            scale: root.shown ? root.uiScale : root.uiScale * 0.85
            opacity: root.shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Canvas {
                id: cv
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate

                readonly property int   sz: 760
                readonly property real  cx: 380
                readonly property real  cy: 380
                readonly property real  tau: Math.PI * 2
                readonly property int   r1i: 94
                readonly property int   r1o: 190
                readonly property int   r2o: 304
                readonly property int   rOuter: 362
                readonly property int   hoverPop: 16
                readonly property int   optOut: 200
                readonly property int   centerDead: 58
                readonly property real  gap: 0.025
                readonly property real  cellAng: 0.65
                readonly property int   pulseBars: 60
                readonly property int   pulseRin: 47
                readonly property int   pulseBarLen: 42

                property var segs: [
                    { label:"Apps",      icon:"\uf009", color:"#5aa6ff", isApp:true,  subs: root.appFavorites },
                    { label:"Apagado",   icon:"\u23fb", color:"#ff5c5c", subs:[
                        {label:"Apagar",icon:"\uf011",color:"#ff4d4d", cmd:["systemctl", "poweroff"]},
                        {label:"Reiniciar",icon:"\uf021",color:"#5aa6ff", cmd:["systemctl", "reboot"]},
                        {label:"Hibernar",icon:"\uf186",color:"#cba6f7", cmd:["systemctl", "hibernate"]},
                        {label:"Sesión",icon:"\uf2f5",color:"#ffb35a", cmd:["hyprctl", "dispatch", "exit"]},
                        {label:"Bloquear",icon:"\uf023",color:"#ffd35a", cmd:["hyprlock"]}] },
                    { label:"Wallpaper", icon:"\uf03e", color:"#7ee787", subs:[
                        {label:"Elegir",icon:"\uf07c",color:"#7ee787"},
                        {label:"Aleatorio",icon:"\uf074",color:"#5ce0a0"}] },
                    { label:"PC",        icon:"\uf108", color:"#ffd35a", isStat:true, subs:[] },
                    { label:"Captura",   icon:"\uf030", color:"#5ce0e6", subs:[
                        {label:"Grabar",icon:"\uf03d",color:"#5ce0e6", cmd:["wl-screenrec"]},
                        {label:"Área video",icon:"\uf0c8",color:"#5ce0e6", cmd:["wl-screenrec", "-g", "$(slurp)"]},
                        {label:"Foto full",icon:"\uf030",color:"#89dceb", cmd:["grim"]},
                        {label:"Foto área",icon:"\uf125",color:"#89dceb", cmd:["sh", "-c", "grim -g \"$(slurp)\" - | wl-copy"]}] }
                ]
                readonly property int  segN: segs.length
                readonly property real segA: tau / segN

                property var pulseValues: []
                property var pulseTargets: []
                property real beatIntensity: 0
                property real introMenu: 0
                property var segP: []
                property var subP: []
                property real subExpandP: 0
                property int subExpandSeg: -1
                property int hSeg: -1
                property int hSub: -1
                property int armedSeg: -1
                property real introStart: 0
                property real lastT: 0
                property bool needDraw: true

                function reset() {
                    pulseValues = []; pulseTargets = [];
                    for (var i = 0; i < pulseBars; i++) { pulseValues.push(0); pulseTargets.push(0); }
                    segP = []; subP = [];
                    for (var s = 0; s < segN; s++) {
                        segP.push(0);
                        var arr = [], ns = (segs[s].subs || []).length;
                        for (var j = 0; j < ns; j++) arr.push(0);
                        subP.push(arr);
                    }
                    subExpandP = 0; subExpandSeg = -1; hSeg = -1; hSub = -1; armedSeg = -1;
                    introMenu = 0; introStart = Date.now(); lastT = 0; beatIntensity = 0; needDraw = true;
                }

                function clamp(x,a,b){ return Math.max(a, Math.min(b,x)); }
                function lerp(a,b,t){ return a+(b-a)*t; }
                function easeOut(t){ return 1-Math.pow(1-t,2.8); }
                function easeInOut(t){ return t<0.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2; }
                function hexToRgb(h){ h=(""+h).replace('#',''); if(h.length===3)h=h.split('').map(function(c){return c+c;}).join(''); return [parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)]; }
                function rgba(hex,a){ var c=hexToRgb(hex); return "rgba("+c[0]+","+c[1]+","+c[2]+","+a+")"; }
                function mixHex(a,b,t){ var c1=hexToRgb(a),c2=hexToRgb(b); function m(i){return Math.round(c1[i]+(c2[i]-c1[i])*t);} function h(x){var s=x.toString(16);return s.length<2?'0'+s:s;} return '#'+h(m(0))+h(m(1))+h(m(2)); }
                function colHex(c){ function h(x){var s=Math.round(x*255).toString(16);return s.length<2?'0'+s:s;} return '#'+h(c.r)+h(c.g)+h(c.b); }
                function relLum(hex){ var c=hexToRgb(hex); return (0.2126*c[0]+0.7152*c[1]+0.0722*c[2])/255; }
                function safeAccent(hex){ var c=hexToRgb(hex),r=c[0],g=c[1],b=c[2],lum=relLum(hex); if(lum<0.5){var t=clamp((0.5-lum)/0.5,0,1)*0.9;r=Math.round(r+(255-r)*t);g=Math.round(g+(255-g)*t);b=Math.round(b+(255-b)*t);} function h(x){var s=x.toString(16);return s.length<2?'0'+s:s;} return '#'+h(r)+h(g)+h(b); }
                function pol(a,r){ return [cx+Math.cos(a)*r, cy+Math.sin(a)*r]; }
                function segStart(i){ return -Math.PI/2 + i*segA; }
                function segMid(i){ return segStart(i)+segA/2; }
                function subSpan(seg){ return Math.max(segA*1.25, Math.min(3.4, seg.subs.length*cellAng)); }
                function subIndexArc(idx,raw){
                    var seg=segs[idx], ns=seg.subs.length, span=subSpan(seg), a0=segMid(idx)-span/2;
                    if (ns === 0) return -1;
                    var rel=((raw-a0)%tau+tau)%tau;
                    if(rel<=span) return clamp(Math.floor(rel/(span/ns)),0,ns-1);
                    return (rel-span)<(tau-rel)?ns-1:0;
                }
                function bodyHex(){ return colHex(root.barBg); }

                function setCava(line){
                    if(!line || line.length<3) return;
                    var parts=line.split(";"), vals=[];
                    for(var i=0;i<parts.length;i++){ if(parts[i]==="")continue; vals.push(clamp(parseFloat(parts[i])/1000,0,1)); }
                    if(!vals.length) return;
                    for(var b=0;b<pulseBars;b++){ var idx=Math.min(vals.length-1, Math.floor(b/pulseBars*vals.length)); pulseTargets[b]=vals[idx]; }
                }

                function roundedSectorPath(ctx,ri,ro,a0,a1,r){
                    var th=ro-ri, span=a1-a0;
                    r=Math.max(0,Math.min(r, th/2, span*ri*0.48, span*ro*0.48));
                    if(r<0.6){ ctx.beginPath();ctx.arc(cx,cy,ro,a0,a1);ctx.arc(cx,cy,ri,a1,a0,true);ctx.closePath();return; }
                    var aoO=r/ro, aoI=r/ri, p, e;
                    ctx.beginPath();
                    p=pol(a0+aoO,ro); ctx.moveTo(p[0],p[1]);
                    ctx.arc(cx,cy,ro,a0+aoO,a1-aoO);
                    p=pol(a1,ro); e=pol(a1,ro-r); ctx.quadraticCurveTo(p[0],p[1],e[0],e[1]);
                    e=pol(a1,ri+r); ctx.lineTo(e[0],e[1]);
                    p=pol(a1,ri); e=pol(a1-aoI,ri); ctx.quadraticCurveTo(p[0],p[1],e[0],e[1]);
                    ctx.arc(cx,cy,ri,a1-aoI,a0+aoI,true);
                    p=pol(a0,ri); e=pol(a0,ri+r); ctx.quadraticCurveTo(p[0],p[1],e[0],e[1]);
                    e=pol(a0,ro-r); ctx.lineTo(e[0],e[1]);
                    p=pol(a0,ro); e=pol(a0+aoO,ro); ctx.quadraticCurveTo(p[0],p[1],e[0],e[1]);
                    ctx.closePath();
                }
                function drawRoundedSector(ctx,ri,ro,a0,a1,r,bodyA,col,strokeA,strokeW,alpha){
                    if(a1<=a0+0.001||alpha<0.005)return;
                    ctx.save(); ctx.globalAlpha=clamp(alpha,0,1);
                    roundedSectorPath(ctx,ri,ro,a0,a1,r);
                    if(bodyA>0.001){ ctx.fillStyle=rgba("#101014", Math.max(0.92, bodyA)); ctx.fill(); }
                    ctx.strokeStyle=rgba(col,strokeA); ctx.lineWidth=strokeW; ctx.stroke();
                    ctx.restore();
                }
                function drawText(ctx,text,x,y,size,color,alpha,font){
                    ctx.save(); ctx.globalAlpha=clamp(alpha,0,1);
                    ctx.font=size+"px '"+(font||'Symbols Nerd Font')+"','Inter',sans-serif";
                    ctx.fillStyle=color; ctx.textAlign='center'; ctx.textBaseline='middle';
                    ctx.fillText(text,x,y); ctx.restore();
                }

                function drawPulseBars(ctx,B,B2,mA){
                    if(mA<0.05) return;
                    var MID=mixHex(B,B2,0.5), step=tau/pulseBars;
                    var sm=[];
                    for(var i=0;i<pulseBars;i++){
                        var pa=pulseValues[(i-1+pulseBars)%pulseBars];
                        var pb=pulseValues[i];
                        var pc=pulseValues[(i+1)%pulseBars];
                        sm[i]=pa*0.25+pb*0.5+pc*0.25;
                    }
                    function pt(i){
                        var ang=-Math.PI/2+(i%pulseBars)*step;
                        var r=pulseRin+sm[i%pulseBars]*pulseBarLen;
                        return [cx+Math.cos(ang)*r, cy+Math.sin(ang)*r];
                    }
                    ctx.save();
                    ctx.beginPath();
                    var p0=pt(0), pl=pt(pulseBars-1);
                    ctx.moveTo((pl[0]+p0[0])/2,(pl[1]+p0[1])/2);
                    for(var i=0;i<pulseBars;i++){
                        var cur=pt(i), nxt=pt((i+1)%pulseBars);
                        ctx.quadraticCurveTo(cur[0],cur[1],(cur[0]+nxt[0])/2,(cur[1]+nxt[1])/2);
                    }
                    ctx.closePath();
                    var grad=ctx.createLinearGradient(cx-rOuter,0,cx+rOuter,0);
                    grad.addColorStop(0,B); grad.addColorStop(0.5,MID); grad.addColorStop(1,B2);
                    ctx.globalAlpha=0.95*mA;
                    ctx.strokeStyle=grad;
                    ctx.lineWidth=2.0;
                    ctx.lineJoin='round';
                    ctx.stroke();
                    ctx.restore();
                }

                onPaint: {
                    var ctx=getContext("2d");
                    var B=safeAccent(colHex(root.accent)), B2=safeAccent(colHex(root.accent2));
                    ctx.clearRect(0,0,sz,sz);
                    var mA=introMenu;
                    var expSeg=(subExpandSeg>=0 && subExpandP>0.01)?subExpandSeg:-1;

                    drawPulseBars(ctx,B,B2,mA);

                    for(var i=0;i<segN;i++){
                        if(i===expSeg) continue;
                        var seg=segs[i],p=easeOut(segP[i]),col=seg.color;
                        var a0=segStart(i)+gap,a1=segStart(i)+segA-gap,ro=lerp(r1o,r1o+8,p);
                        drawRoundedSector(ctx,r1i,ro,a0,a1,12, lerp(0.78,0.92,p), col,lerp(0.40,1,p),lerp(1.6,2.8,p), mA);
                    }

                    var bandL=0,bandSpan=0,rIn=0,rOut=0,optRoExp=0,eItems=null,eNs=0,eCol='#fff';
                    if(expSeg>=0){
                        var segE=segs[expSeg],prog=easeInOut(subExpandP),secMid=segMid(expSeg);
                        eCol=segE.color; eItems=segE.subs||[]; eNs=eItems.length;
                        var aOptL=segStart(expSeg)+gap, aOptR=segStart(expSeg)+segA-gap;

                        optRoExp=lerp(r1o,r1o+28,prog);
                        drawRoundedSector(ctx,r1i,optRoExp,aOptL,aOptR,12, 0.92, eCol,lerp(0.6,1,prog),lerp(2,3.4,prog), mA);

                        if (eNs > 0) {
                            var halfOpt=(aOptR-aOptL)/2;
                            var halfSubFull=subSpan(segE)/2-gap/2, halfSub=lerp(halfOpt,halfSubFull,prog);
                            bandL=secMid-halfSub; bandSpan=2*halfSub;
                            var subA=easeOut(subExpandP)*mA;

                            rIn=optRoExp+lerp(14,22,prog);
                            rOut=lerp(optRoExp+48,r2o+24,prog);
                            var cellSpan=bandSpan/eNs;
                            for(var j=0;j<eNs;j++){
                                var sp=easeOut(subP[expSeg][j]);
                                var b0=bandL+j*cellSpan,b1=bandL+(j+1)*cellSpan,colS=eItems[j].color||eCol;
                                var rOut2=rOut+hoverPop*sp;
                                var ca0=b0+gap*0.6,ca1=b1-gap*0.6,corner=lerp(8,14,sp);
                                ctx.save(); ctx.globalAlpha=subA;
                                roundedSectorPath(ctx,rIn,rOut2,ca0,ca1,corner);
                                ctx.fillStyle=rgba("#101014",0.96); ctx.fill();
                                ctx.fillStyle=rgba(colS,lerp(0.08,0.30,sp)); ctx.fill();
                                ctx.strokeStyle=rgba(colS,lerp(0.5,1,sp)); ctx.lineWidth=lerp(1.4,2.6,sp); ctx.stroke();
                                ctx.restore();
                            }
                        }
                    }

                    for(var k=0;k<segN;k++){
                        var segK=segs[k],pk=easeOut(segP[k]),colK=segK.color;
                        var roK=(k===expSeg)?optRoExp:lerp(r1o,r1o+8,pk);
                        var mid=(r1i+roK)/2,ma=segMid(k),tx=cx+Math.cos(ma)*mid,ty=cy+Math.sin(ma)*mid;
                        drawText(ctx,segK.icon,tx,ty+lerp(2,-10,pk),lerp(18,21,pk),colK,(pk*0.4+0.6)*mA,'Symbols Nerd Font');
                        drawText(ctx,segK.label.toUpperCase(),tx,ty+13,lerp(8,9,pk),colK,pk*mA,'Cantarell');
                    }

                    if(expSeg>=0 && eNs > 0){
                        var cs=bandSpan/eNs, subA2=easeOut(subExpandP)*mA;
                        ctx.save();
                        ctx.globalAlpha=clamp(subA2,0,1);
                        ctx.textAlign='center'; ctx.textBaseline='middle';
                        for(var m=0;m<eNs;m++){
                            var mb0=bandL+m*cs,mb1=bandL+(m+1)*cs,cmid=(mb0+mb1)/2;
                            var item=eItems[m],colM=item.color||eCol,spm=easeOut(subP[expSeg][m]);
                            var rmid=(rIn+(rOut+hoverPop*spm))/2,mtx=cx+Math.cos(cmid)*rmid,mty=cy+Math.sin(cmid)*rmid;
                            
                            // Ícono
                            ctx.font=lerp(16,22,spm)+"px 'Symbols Nerd Font','Cantarell',sans-serif";
                            ctx.fillStyle=colM;
                            ctx.fillText(item.icon||"",mtx,mty-11);
                            
                            // Texto
                            ctx.font=lerp(9.5,12.0,spm)+"px 'Cantarell','Adwaita Sans',sans-serif";
                            ctx.fillText(item.label,mtx,mty+13);
                        }
                        ctx.restore();
                    }
                }

                function handleMove(mx,my){
                    var dx=mx-cx, dy=my-cy, dist=Math.sqrt(dx*dx+dy*dy), raw=Math.atan2(dy,dx);
                    var optIdx=Math.floor((((raw+Math.PI/2)%tau+tau)%tau)/segA)%segN;
                    if(dist<centerDead){ if(hSub!==-1||hSeg!==-1){ hSub=-1; hSeg=(subExpandSeg>=0?subExpandSeg:-1); needDraw=true; } return; }
                    if(dist<=optOut){
                        armedSeg=optIdx;
                        if(hSeg!==optIdx||hSub!==-1){ hSeg=optIdx; hSub=-1; needDraw=true; }
                        if(subExpandSeg !== optIdx) {
                            subExpandSeg = optIdx;
                            subExpandP = 0;
                            needDraw = true;
                        }
                    } else {
                        if(subExpandSeg<0 && armedSeg>=0) {
                            subExpandSeg = armedSeg;
                            subExpandP = 0;
                            needDraw = true;
                        }
                        if(subExpandSeg>=0){
                            var seg=segs[subExpandSeg];
                            if(hSeg!==subExpandSeg){ hSeg=subExpandSeg; needDraw=true; }
                            if (seg.subs && seg.subs.length > 0) {
                                var ns=subIndexArc(subExpandSeg,raw);
                                if(hSub!==ns){ hSub=ns; needDraw=true; }
                            } else {
                                if(hSub!==-1){ hSub=-1; needDraw=true; }
                            }
                        } else {
                            if(hSeg!==optIdx||hSub!==-1){ hSeg=optIdx; hSub=-1; needDraw=true; }
                        }
                    }
                }

                function activate(){
                    if(subExpandSeg>=0){
                        var seg=segs[subExpandSeg];
                        if(seg.label==="Wallpaper"){
                            if(hSub===1) root.requestWallpaperRandom(); else root.requestWallpaper();
                            root.close(); return;
                        }
                        if(seg.subs && hSub>=0 && hSub < seg.subs.length){
                            var item = seg.subs[hSub];
                            if(item.cmd){
                                execProc.command = item.cmd;
                                execProc.running = true;
                                root.close(); return;
                            }
                        }
                    }
                    root.close();
                }

                Timer {
                    interval: 16; running: root.shown; repeat: true
                    onTriggered: {
                        var now=Date.now();
                        if(!cv.lastT) cv.lastT=now;
                        var dt=cv.clamp((now-cv.lastT)/1000,0,0.05); cv.lastT=now;
                        var it=(now-cv.introStart)/1000;
                        cv.introMenu=cv.easeOut(cv.clamp(it/0.5,0,1));
                        var moving = cv.introMenu<1;
                        for(var i=0;i<cv.pulseBars;i++){ var d=cv.pulseTargets[i]-cv.pulseValues[i]; var spd=d>0?26:10;
                            if(Math.abs(d)>0.002){ cv.pulseValues[i]+=d*Math.min(1,spd*dt); moving=true; } }
                        var nb=Math.max(1,Math.floor(cv.pulseBars*0.12)), bass=0;
                        for(var b=0;b<nb;b++) bass+=cv.pulseValues[b];
                        cv.beatIntensity=cv.clamp(bass/nb,0,1);
                        for(var s=0;s<cv.segN;s++){
                            var tg=(cv.hSeg===s)?1:0, np=cv.clamp(cv.segP[s]+(tg-cv.segP[s])*10*dt,0,1);
                            if(Math.abs(np-cv.segP[s])>0.0005)moving=true; cv.segP[s]=np;
                            var subs=cv.segs[s].subs||[];
                            for(var j=0;j<subs.length;j++){ var stt=(cv.hSeg===s&&cv.hSub===j)?1:0;
                                var rate=(stt>cv.subP[s][j])?10:7, nsp=cv.clamp(cv.subP[s][j]+(stt-cv.subP[s][j])*rate*dt,0,1);
                                if(Math.abs(nsp-cv.subP[s][j])>0.0005)moving=true; cv.subP[s][j]=nsp; }
                        }
                        var te=(cv.subExpandSeg>=0)?1:0, nE=cv.clamp(cv.subExpandP+(te-cv.subExpandP)*5*dt,0,1);
                        if(Math.abs(nE-cv.subExpandP)>0.0005)moving=true; cv.subExpandP=nE;
                        if(moving||cv.needDraw){ cv.requestPaint(); cv.needDraw=false; }
                    }
                }

                Component.onCompleted: reset()
            }

            Rectangle {
                id: avatarWrap
                width: 94; height: 94; radius: 47
                anchors.centerIn: parent
                color: root.barBg
                border.width: 2; border.color: root.accent
                clip: true
                scale: 1 + cv.beatIntensity * 0.06
                Image {
                    id: avatarImg
                    anchors.fill: parent
                    source: "file:///home/arise/.config/serafin/avatar.png"
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatarImg.status !== Image.Ready
                    text: "\uf2c1"
                    color: root.accent
                    font.family: "Symbols Nerd Font"; font.pixelSize: 40
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: (m) => cv.handleMove(m.x, m.y)
                onClicked: (m) => {
                    var dx = m.x - 380, dy = m.y - 380;
                    if (Math.sqrt(dx*dx + dy*dy) <= 47) {
                        avatarPicker.open();
                    } else {
                        cv.activate();
                    }
                }
            }
        }
    }
}
