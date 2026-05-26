# widgets/ — Design System & Patterns

Guía de diseño para los widgets de Ambxst (dock, sidebar, panels, popups). Establece
el lenguaje visual, patrones de QML reutilizables y anti-patterns descubiertos
al construir el RightDock con 4 tabs creativos (calendar, weather, pomodoro,
color picker).

> **Cuando estés agregando un widget nuevo**, leé esto primero. Te ahorra
> 80% de los bugs de QML que ya pisamos.

## VISUAL LANGUAGE

### Capas verticales de un tab/panel inmersivo

```
┌──────────────────────────────────────────┐
│ Layer 0: ambient background              │  ← gradient + opcional partículas
│   - color/gradient temático              │
│   - decoraciones procedurales            │
│     (sol, luna, lluvia, nubes, ...)      │
├──────────────────────────────────────────┤
│ Layer 1: glass content cards             │  ← rgba dark + border claro
│   - Hero card (focal element)            │
│   - Stats / data cards                   │
│   - Action buttons                       │
└──────────────────────────────────────────┘
```

Patrón base:

```qml
Item {
    id: tabRoot
    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 24

    // Background layer (gradient + animations)
    Rectangle {
        id: tabBg
        anchors.fill: parent
        radius: Styling.radius(8)
        clip: true
        // gradient: ...
        // children: particles / decorations
    }

    // Content layer (glass cards)
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        // Rectangles con look "glass" abajo
    }
}
```

### Glass card spec

```qml
Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: <content height>
    color: Qt.rgba(0, 0, 0, 0.32)      // 0.30–0.38 según contraste con bg
    radius: 12                          // 14 para hero cards, 12 para resto
    border.color: Qt.rgba(1, 1, 1, 0.12) // 0.10–0.20
    border.width: 1
}
```

**Texto sobre glass card** — siempre blanco con opacities:

| Opacity | Uso |
|---|---|
| `"white"` (1.0) | Texto principal (valores, hex, temps grandes) |
| `Qt.rgba(1,1,1,0.78)` | Texto secundario (descripciones) |
| `Qt.rgba(1,1,1,0.6)` | Section headers ("Today", "Formats", "Harmonies") |
| `Qt.rgba(1,1,1,0.55)` | Labels secundarios |
| `Qt.rgba(1,1,1,0.5)` | Texto muy menor |

## CARD PATTERNS

### 1. Hero card (focal element)

Ocupa la parte superior del tab. Contiene el elemento más importante (analog
clock, current weather, big color preview, pomodoro tomato, etc).

**Altura típica**: 110–340px

**Ejemplo**: `RightDock.qml` `clockHeaderPane`, `mainWeatherPane`, color HERO.

### 2. Stats grid

Fila de N mini-cards con métrica + label. Idealmente 3–4 columnas.

```qml
Row {
    Layout.fillWidth: true
    spacing: 8
    Repeater {
        model: [
            { ico: "💧", lab: "humid", val: "65%" },
            { ico: "☀️", lab: "UV",    val: "3.2" },
            // ...
        ]
        Rectangle {
            width: (parent.width - spacing*(N-1)) / N
            // glass card props
            Column { /* icon + value + label */ }
        }
    }
}
```

### 3. Action buttons (glass + hover)

Para botones grandes o iconos clickeables:

```qml
Rectangle {
    width: 50; height: 50; radius: 12
    color: mouse.containsMouse ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.32)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }
    // contenido
    MouseArea { id: mouse; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
}
```

### 4. Tinted action button (al color de estado)

Para el botón principal que refleja el estado (apply color, primary action):

```qml
Rectangle {
    color: mouse.containsMouse ? someColor : Qt.darker(someColor, 1.3)
    Behavior on color { ColorAnimation { duration: 160 } }
}
```

## ANIMATION PATTERNS

### Partículas flotantes (rain / dust / stars / confetti)

```qml
Repeater {
    model: 30
    Rectangle {
        required property int index
        x: Math.random() * parent.width
        width: 2; height: 8
        color: Qt.rgba(...)
        SequentialAnimation on y {
            loops: Animation.Infinite
            NumberAnimation {
                from: -10; to: parent.height + 10
                duration: 800 + Math.random() * 800
                easing.type: Easing.InQuad
            }
        }
    }
}
```

**Variantes**:
- Lluvia: `from: -10; to: height+10`, duration 800–1600ms
- Dust motes (suben): `from: height+10; to: -10`, duration 6000–12000ms
- Stars titilando: solo `SequentialAnimation on opacity` con valores 0.2 ↔ 1.0
- Snow: combinar `y` con `x` sinusoidal (sway) usando otra `SequentialAnimation on x`

### Pulse / breathing

```qml
SequentialAnimation on scale {
    running: someCondition
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 1.06; duration: 1500; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1.06; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
}
```

### Wobble (click feedback)

```qml
transform: Rotation { id: wob; origin.x: w/2; origin.y: h/2; angle: 0 }
SequentialAnimation {
    id: wobAnim
    NumberAnimation { target: wob; property: "angle"; to: -8; duration: 80 }
    NumberAnimation { target: wob; property: "angle"; to: 8;  duration: 120 }
    NumberAnimation { target: wob; property: "angle"; to: -4; duration: 100 }
    NumberAnimation { target: wob; property: "angle"; to: 0;  duration: 100 }
}
MouseArea { onClicked: wobAnim.restart() }
```

### Smooth gradient transitions

```qml
GradientStop {
    color: someCondition ? "#ff9c5c" : "#5dadeb"
    Behavior on color { ColorAnimation { duration: 1500 } }
}
```

**Duraciones recomendadas**:
- Hover/click: 120–200ms
- State change (color, opacity): 250–600ms
- Ambient transitions (time-of-day, weather): 1500–3000ms

### Fade-text-on-change (quote rotativa)

`Behavior on text` **NO funciona** para strings. Usar SequentialAnimation manual:

```qml
SequentialAnimation {
    id: rotateAnim
    NumberAnimation { target: textNode; property: "opacity"; to: 0; duration: 280 }
    ScriptAction { script: textNode.text = nextValue }
    NumberAnimation { target: textNode; property: "opacity"; to: 1; duration: 280 }
}
```

## LAYOUT RULES

### Usar `ColumnLayout` / `RowLayout` (no `Column` / `Row`) para inmersivos

`Column` y `Row` son Positioners. **No respetan height/width de hijos que
usan `anchors`** → los hijos se apilan como si tuvieran size=0 → overlap.

❌ **No mezclar**:
```qml
Column {
    Item { anchors.horizontalCenter: parent.horizontalCenter; height: 50 }  // BUG
}
```

✅ **Hacer así**:
```qml
ColumnLayout {
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: 50
    }
}
```

**Cuándo Column es OK**: cuando los hijos NO usan anchors y tienen height
explícito o implicit. Útil para contenido lineal simple sin centrado.

### `Layout.preferredHeight` en cards

Siempre explícito. Para contenido dinámico:

```qml
Rectangle {
    Layout.preferredHeight: innerColumn.implicitHeight + 24  // padding
}
```

### Tab structure dentro de StackLayout

```qml
StackLayout {
    currentIndex: dock.currentTab
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12

    // Each tab is an Item or Layout
    Item { /* tab 0 */ }
    Item { /* tab 1 */ }
    // ...
}
```

## QML PITFALLS (lecciones del RightDock)

### 1. `parent.foo` no resuelve dentro de `GradientStop`

```qml
Rectangle {
    function topColor(h) { ... }
    gradient: Gradient {
        GradientStop {
            color: parent.topColor(h)  // ❌ parent === Gradient, no Rectangle
        }
    }
}
```

✅ **Fix**: dar id al Rectangle:

```qml
Rectangle {
    id: bg
    function topColor(h) { ... }
    gradient: Gradient {
        GradientStop { color: bg.topColor(h) }
    }
}
```

### 2. `RadialGradient` NO es un tipo de `Rectangle.gradient`

`Rectangle.gradient` solo acepta `Gradient` linear. Para radial, simular con
N círculos concéntricos con opacidad decreciente:

```qml
Rectangle { width: 100; height: 100; radius: 50; color: Qt.rgba(1,1,0,0.15) }
Rectangle { width: 70;  height: 70;  radius: 35; color: Qt.rgba(1,1,0,0.30) }
Rectangle { width: 50;  height: 50;  radius: 25; color: "#fcc14e" }
```

### 3. `Behavior on <listProperty>` no funciona

`text`, `color` arrays, etc. no son animables directamente. Usar
`SequentialAnimation` con `ScriptAction` para el cambio + opacity fade.

### 4. Anchors dentro de Column/Row Positioners

Conflicto silencioso. Mover a ColumnLayout/RowLayout.

### 5. Duplicate property bindings al refactorizar

Cuando cambiás `StyledRect { variant: "pane"; radius: ... }` → `Rectangle { color: ...; radius: ... }`, asegurate que NO queden bindings viejos.
qmllint NO detecta esto. Quickshell falla con:

```
QML RightDock: Property value set multiple times
```

Estrategia: borrar y re-escribir el bloque entero, no solo la primera línea.

### 6. `ln -sf` crea self-links en directorios symlinkeados

Si el target ya es symlink-a-dir, `ln -sf` crea un nuevo symlink DENTRO en
vez de reemplazar. **Siempre usar `ln -sfn`** en install.sh.

### 7. Repeater model con `parent.parent.xxx`

Funciona pero frágil. Mejor dar id al ancestor y referenciarlo directo.

### 8. `pragma ComponentBehavior: Bound` requiere `required property`

Si el archivo lo declara, todos los Repeater/Component delegates necesitan
`required property var modelData` (etc).

## FONT USAGE

```qml
// Cuerpo / labels
font.family: Config.theme.font
font.pixelSize: Styling.fontSize(0)

// Números / código / hex
font.family: Config.theme.monoFont
font.pixelSize: Styling.fontSize(0)

// Icons (Phosphor)
font.family: Icons.font
text: Icons.timer  // u otro
font.pixelSize: 22
```

### Tamaños (Styling.fontSize)

| Llamada | Px aprox | Uso |
|---|---|---|
| `-2` | 9–10 | Tooltips, labels muy menores |
| `-1` | 11–12 | Labels secundarios, section headers |
| `0` | 13–14 | Body default |
| `1` | 15–16 | Body destacado |
| `2` | 17–19 | Subtítulos |
| `3` | 20–24 | Títulos pequeños |
| `4` | 26–30 | Números destacados (stats) |
| `7` | 50–60 | Display (clocks, big temp) |

### Font weight

- `Font.Light`: display grande (clocks 32-52px)
- `Font.Normal`: body default
- `Font.Medium`: labels de sección
- `Font.Bold`: stats / valores destacados

## COLOR USAGE

### Matugen palette

Disponible en `qs.modules.theme.Colors`:
- `Colors.primary` — accent principal
- `Colors.secondary` / `Colors.tertiary` — accents secundarios
- `Colors.error` — destructivos / alerts
- `Colors.background` / `Colors.surface` — bg matugen
- `Colors.overBackground` / `Colors.outline` — text/border sobre bg matugen

### Cuándo usar matugen vs colors hardcoded

| Caso | Approach |
|---|---|
| Ambient bg (weather, time-of-day) | Hardcoded — el contexto pide colores específicos (azul para mañana, naranja para sunset) |
| Glass cards | Hardcoded `rgba(0,0,0,0.32)` + texto blanco — para que funcione sobre cualquier ambient bg |
| Accent elements (botones primary, progress fills, focus rings) | `Colors.primary` matugen — adapta con el wallpaper |
| Color picker harmonies | Derivar de hsvPicker.resultColor |

### `Qt.darker` / `Qt.lighter`

```qml
color: Qt.darker(Colors.primary, 1.4)  // 1.0 = igual, >1 = más oscuro
color: Qt.lighter(Colors.secondary, 1.1)
```

Útil para gradient stops sin hardcodear colores específicos.

## PROCESS / IPC PATTERNS

### Fire-and-forget (sin response)

```qml
Quickshell.execDetached(["matugen", "color", "hex", hsvPicker.hexValue]);
Quickshell.execDetached(["notify-send", "-t", "1500", "Title", "Body"]);
```

### Process con readback (eyedropper)

```qml
import Quickshell.Io  // imprescindible

Process {
    id: proc
    command: ["sh", "-c", "..."]
    stdout: StdioCollector {
        onStreamFinished: {
            var result = this.text.trim();
            // procesar
        }
    }
}

// Trigger
proc.running = true
```

### Socket2 listener (eventos hyprland)

Ver `bin/yazi-portal-wrapper` y la idea descartada en `bin/portal-picker-floater`
(antes de que `hyprctl dispatch exec [rules]` resolviera el caso).

## PERFORMANCE GUIDELINES

### Timer scope

Los timers SOLO deben correr cuando el contenido es visible:

```qml
Timer {
    interval: 1000
    running: dock.isOpen && dock.currentTab === 0  // tab visible
    repeat: true
    triggeredOnStart: true
    onTriggered: now = new Date()
}
```

### Particle count

| Tipo | Cantidad recomendada |
|---|---|
| Estrellas titilando | 30–60 |
| Lluvia | 60–80 |
| Tormenta (rain intenso) | 80–100 |
| Dust motes / confetti suave | 18–32 |
| Niebla (rectángulos grandes) | 5–8 |

Más de 100 partículas con animations Infinite empieza a notarse en CPU.

### `running` flag en SequentialAnimation

Si la animación es decorativa, condicionarla a `dock.isOpen && currentTab === X`
para que no consuma CPU cuando no se ve.

## ANTI-PATTERNS

- ❌ **Hardcodear colores matugen** (`#ba3c0b`). Siempre `Colors.primary` etc.
- ❌ **Glass cards sobre matugen bg** sin background ambient — pierden gracia. Usar rgba dark sobre bg colorido.
- ❌ **`anchors.centerIn` dentro de Positioner** (Column/Row).
- ❌ **`Behavior` sobre strings / arrays** — silenciosamente no funciona.
- ❌ **Más de 100 particles infinitas** simultáneas.
- ❌ **Timers `running: true` sin condicionar a visibilidad** del widget.
- ❌ **Modificar `parent.foo` sin asegurar que `parent` es el item esperado** (especialmente dentro de GradientStop, Connections, model delegates).

## EXAMPLES IN THE CODEBASE

| Pattern | Archivo | Líneas aprox |
|---|---|---|
| Tab estructura (Item + bg + ColumnLayout) | `rightdock/RightDock.qml` | TAB 0, 1, 2, 3 |
| Time-of-day gradient + particles | `rightdock/RightDock.qml` calendarBg | TAB 0 |
| Weather animations (rain/sun/snow/etc) | `rightdock/RightDock.qml` Components | TAB 1 (sunnyAnim, rainAnim, etc.) |
| Pomodoro pulse + wobble + ring progress | `rightdock/RightDock.qml` TAB 2 | tomatoStage |
| Color immersive + bidirectional formats | `rightdock/RightDock.qml` TAB 3 | formatsCard |
| Tab rail (vertical icon strip) | `rightdock/RightDock.qml` | tabRailBg |
| Shoulders cóncavos (notch-style) | `rightdock/RightDock.qml` + `bar/BarContent.qml` | bottomLeftShoulder, topLeftShoulder |
| Process readback (eyedropper) | `rightdock/RightDock.qml` | eyedropProc |
| Quote rotativa con fade | `rightdock/RightDock.qml` TAB 2 | quotePane |
| Stats animados (count + flame pulse) | `rightdock/RightDock.qml` TAB 2 | streak counter |

## CUANDO AGREGAR UN WIDGET NUEVO

1. **Decidir el vibe**: lofi (Pomodoro), animated atmosphere (Weather, Calendar),
   immersive color (Color picker), o minimal con animaciones sutiles.

2. **Layout base**: copiar el patrón Item + bg + ColumnLayout de los tabs existentes.

3. **Glass cards**: usar el spec arriba (`rgba(0,0,0,0.32)` + border + radius).

4. **Animaciones**: empezar con 1-2 (particles + un pulse). Agregar más después si
   se siente vacío. Más no = mejor.

5. **Lint + run**: `qmllint` solo detecta sintaxis. Para semánticos, lanzar
   `qs -p shell.qml` y leer stderr buscando `Property value set multiple times`,
   `ReferenceError`, etc.

6. **Performance check**: si el widget tiene animations en loop, condicionar `running` a `visible && open`.

7. **Documentar**: si el widget tiene un patrón NUEVO o un bug que costó, agregarlo
   a este DESIGN.md.
