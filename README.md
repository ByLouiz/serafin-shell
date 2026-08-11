# Serafín Shell 🪽

Barra + visualizador de audio (domo/pulse) + menú radial Halo para [Quickshell](https://github.com/outfoxxed/quickshell) (QML), temática angelical con estética glassmorphism.

Corre con: `qs -c serafin`

## Estructura

```
├── shell.qml        → Barra principal, Pulse, App Launcher Caelestia
├── Halo.qml         → Menú radial con subopciones, stats del sistema y favoritos
├── Wallpapers.qml   → Selector de wallpapers con paralelogramos
├── cava.conf        → Configuración de CAVA para el visualizador de audio
├── colors.json      → Colores del tema (generado por matugen, no versionado)
├── bin/
│   ├── serafin-wall      → Script para cambiar wallpaper + recolorear
│   ├── serafin-thumbs    → Generador de thumbnails de wallpapers
│   └── serafin-backup    → Script de respaldo
├── hypr/
│   └── hyprland.conf     → Configuración de Hyprland
└── matugen/
    ├── config.toml       → Configuración de matugen
    └── templates/        → Plantillas de colores
```

## Características

- **Barra inferior** con reloj, volumen, batería, búsqueda y widgets
- **Pulse** — Domo vectorial con visualización de audio en tiempo real (CAVA)
- **Halo** — Menú radial con sectores para Apps, Apagado, Wallpaper y Widgets del sistema (CPU, RAM, Disco)
- **App Launcher Caelestia** — Buscador de aplicaciones con animación elástica desde el borde superior
- **Sistema de Favoritos** — Apps favoritas persistentes que aparecen como subopciones dinámicas en el Halo
- **Selector de Wallpapers** — Grid con paralelogramos y cambio dinámico de colores via matugen

## Dependencias

- [Quickshell](https://github.com/outfoxxed/quickshell)
- [Hyprland](https://hyprland.org/)
- [CAVA](https://github.com/karlstav/cava)
- [matugen](https://github.com/InioX/matugen)

## Autor

Por **ByLouiz**.
