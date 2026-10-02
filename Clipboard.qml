import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "Store.js" as Store
import "Fuzzy.js" as Fuzzy
import "Classify.js" as Classify
import "Actions.js" as Actions
import "Snippets.js" as Snippets
import "lang/en.js" as En
import "lang/es.js" as Es

// Clipboard history picker — Raycast-style: fuzzy search bar, result list,
// and a per-type preview pane. Clone of omarchy.clipboard with richer
// capture metadata (app, size, dims, pins, usage) and full-text fuzzy filtering.
Item {
  id: root

  property bool opened: false

  // Idioma de la interfaz (setting `language`, inglés por defecto). Todo texto
  // visible sale de lang/<idioma>.js vía t(); lo que falte cae al inglés.
  readonly property var strings: root.settings.language === "es" ? Es.strings : En.strings
  function t(key, args) {
    var s = root.strings[key]
    if (s === undefined) s = En.strings[key]
    if (s === undefined) return String(key)
    if (!args) return s
    return String(s).replace(/\{(\w+)\}/g, function(m, k) { return args[k] !== undefined ? String(args[k]) : m })
  }

  // Pestañas del picker, en orden: ← / → se mueven entre ellas.
  readonly property var tabs: [
    { key: "clipboard", label: "tab.clipboard", icon: "󰅌" },
    { key: "snippets", label: "tab.snippets", icon: "󰅴" }
  ]
  property string activeTab: "clipboard"
  // Filtros por tipo. Ctrl+F entra en "modo filtros": ← / → se mueven entre
  // ellos (y lo aplican) en vez de cambiar de pestaña; Esc, Enter, otra tecla
  // o un clic fuera de los filtros salen del modo.
  readonly property var typeChips: [
    { key: "", icon: "", label: "chip.all" },
    { key: "text", icon: "󰈙", label: "chip.text" },
    { key: "link", icon: "󰌹", label: "chip.links" },
    { key: "image", icon: "󰋲", label: "chip.images" },
    { key: "files", icon: "󰉋", label: "chip.files" },
    { key: "code", icon: "󰅴", label: "chip.code" },
    { key: "json", icon: "󰘦", label: "chip.json" },
    { key: "color", icon: "󰏘", label: "chip.colors" },
    { key: "pinned", icon: "★", label: "chip.pinned" }
  ]
  property bool chipMode: false
  property string filterText: ""
  property string typeFilter: "" // chip filter, "" = all; combined into the query
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool cursorVisible: true
  property bool clearConfirmOpen: false
  property var history: []
  property var results: [] // [{ row, score, positions }] — fijados primero (groupPinned)
  property var pinIds: [] // ids de los pines en su orden fijo: pinIds[0] es Ctrl+1
  property int pinnedShown: 0 // cuántos de `results` son fijados (el grupo de arriba)

  property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  // Todo el estado vive en una carpeta propia, aparte de omarchy.clipboard y de
  // cualquier otro plugin (ver docs/REFERENCES.md, lecciones de las pruebas).
  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/super-clipboard-snippet"
  property string statePath: stateDir + "/history.json"
  property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/super-clipboard-snippet"
  property var settings: Store.defaultSettings()
  property int historyLimit: 1500
  property int displayLimit: 200
  property int maxAgeDays: 0 // 0 = keep forever
  property bool qrDecode: true
  property bool ocr: true
  property string ocrLang: "eng"
  property bool paused: false
  property var typeCache: ({}) // id → derived type, memoized

  // Theme surface tokens (menu) — tracks the active Omarchy theme.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, 1) // borde fino
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  // Aviso de "en pausa": rojo fijo, no Color.urgent, que en algunos temas es gris.
  readonly property color pausedColor: "#e06c75"
  property color mutedFg: Util.alpha(foreground, 0.55)
  // Hora y tamaño bajo cada clip: más apagado que mutedFg para que no compita con el título.
  property color rowMetaFg: Util.alpha(foreground, 0.38)
  property color chipBg: Util.alpha(foreground, 0.07)
  property color lineColor: Util.alpha(foreground, 0.14)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2)
  // Tamaño (setting `size`): compacto = ventana, filas y miniaturas más chicas.
  readonly property bool compactUi: root.settings.size === "compact"
  readonly property int cardWidth: compactUi ? Style.space(810) : Style.space(980)
  readonly property int cardHeight: compactUi ? Style.space(520) : Style.space(680)
  readonly property int rowHeight: compactUi ? Style.space(42) : Style.space(52)
  readonly property int thumbSize: compactUi ? Style.space(28) : Style.space(36)
  // Filas fijadas: finas y sin línea de detalle (siempre están ahí; repetir
  // tipo/app/fecha en cada una cansa). El detalle sigue en el preview.
  readonly property int pinnedRowHeight: compactUi ? Style.space(30) : Style.space(34)
  readonly property int listWidth: Math.round(card.width * 0.46)

  // Aparición propia (fade + escala leve). La animación de capas de Hyprland es
  // global y lenta (400 ms al entrar); el namespace "omarchy-clipboard" la apaga
  // (regla de Omarchy en default/hypr/apps/omarchy-shell.lua) y aquí se marca el ritmo.
  readonly property int fadeInMs: 120
  readonly property int fadeOutMs: 90
  readonly property real scrimAlpha: 0.28 // fondo oscurecido, leve
  property real reveal: opened ? 1 : 0
  Behavior on reveal {
    NumberAnimation { duration: root.opened ? root.fadeInMs : root.fadeOutMs; easing.type: Easing.OutCubic }
  }
  readonly property bool surfaceVisible: opened || reveal > 0.001

  // Posición (setting `position`): en el centro, o con la esquina de la tarjeta
  // junto al puntero (lo da hyprctl al abrir) y siempre dentro de la pantalla.
  readonly property bool atCursor: root.settings.position === "cursor"
  property real cardX: 0
  property real cardY: 0

  function placeAtCursor(raw) {
    var pos = null
    try { pos = JSON.parse(String(raw || "")) } catch (e) { pos = null }
    var sx = panel.screen ? panel.screen.x : 0
    var sy = panel.screen ? panel.screen.y : 0
    var m = Style.space(12)
    var x = pos ? Number(pos.x) - sx - Style.space(24) : (panel.width - root.cardWidth) / 2
    var y = pos ? Number(pos.y) - sy - Style.space(16) : (panel.height - root.cardHeight) / 2
    root.cardX = Math.max(m, Math.min(panel.width - root.cardWidth - m, x))
    root.cardY = Math.max(m, Math.min(panel.height - root.cardHeight - m, y))
  }

  readonly property var currentResult: results.length > 0 && selectedIndex >= 0 && selectedIndex < results.length ? results[selectedIndex] : null

  // ------------------------------------------------------------ lifecycle

  function open() {
    if (root.atCursor) {
      root.placeAtCursor("") // centro mientras llega la posición del puntero
      cursorProc.running = true
    }
    root.opened = true
    root.activeTab = "clipboard"
    root.snipQuery = ""
    root.snipIndex = 0
    root.chipMode = false
    root.depsChecked = false
    root.checkDeps()
    root.filterText = ""
    root.typeFilter = ""
    chipsFlick.contentX = 0
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuild()
    // Los pines son curados y casi nunca son lo que se busca al abrir: el cursor
    // cae en el primer clip del historial y con ↑ se sube a los fijados.
    if (root.pinnedShown > 0 && root.pinnedShown < root.results.length) root.selectedIndex = root.pinnedShown
    Qt.callLater(function() {
      resultList.positionViewAtBeginning()
      if (root.results.length > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.cancelClearHistory()
    root.actionsOpen = false
    root.snipEditing = false
    root.varsOpen = false
    root.editing = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  // ------------------------------------------------------------ settings
  // Vista propia (no entra en el ciclo de ← / →): Ctrl+, o el engranaje.
  // Filas con `section` son títulos; el resto se edita con teclado o mouse.
  // label/desc/section y las etiquetas de opción son claves de lang/*.js; una
  // etiqueta que no es clave (p. ej. "500") se muestra tal cual.
  readonly property var settingsRows: [
    { section: "set.section.general" },
    { key: "language", type: "choice", label: "set.language", desc: "set.language.desc",
      options: [{ value: "en", label: "English" }, { value: "es", label: "Español" }] },
    { section: "set.section.appearance" },
    { key: "size", type: "choice", label: "set.size", desc: "set.size.desc",
      options: [{ value: "normal", label: "opt.normal" }, { value: "compact", label: "opt.compact" }] },
    { key: "position", type: "choice", label: "set.position", desc: "set.position.desc",
      options: [{ value: "center", label: "opt.center" }, { value: "cursor", label: "opt.cursor" }] },
    { section: "set.section.shortcuts" },
    { key: "openShortcut", type: "choice", label: "set.openShortcut", desc: "set.openShortcut.desc",
      options: [{ value: "", label: "opt.off" }, { value: "ctrl+shift+v", label: "Ctrl+Shift+V" },
                { value: "super+v", label: "Super+V" }, { value: "super+ctrl+v", label: "Super+Ctrl+V" }] },
    { key: "quickShortcut", type: "choice", label: "set.quickShortcut", desc: "set.quickShortcut.desc",
      options: [{ value: "", label: "opt.off" }, { value: "ctrl+space", label: "Ctrl+Space" },
                { value: "ctrl+shift+space", label: "Ctrl+Shift+Space" }, { value: "super+ctrl+space", label: "Super+Ctrl+Space" }] },
    { section: "set.section.behavior" },
    { key: "closeOnClickOutside", type: "bool", label: "set.closeOutside", desc: "set.closeOutside.desc" },
    { key: "confirmDelete", type: "bool", label: "set.confirmDelete", desc: "set.confirmDelete.desc" },
    { section: "set.section.history" },
    { key: "historyLimit", type: "choice", label: "set.historyLimit", desc: "set.historyLimit.desc",
      options: [{ value: "300", label: "300" }, { value: "500", label: "500" }, { value: "1000", label: "1000" },
                { value: "1500", label: "1500" }, { value: "3000", label: "3000" }, { value: "5000", label: "5000" }] },
    { key: "maxAgeDays", type: "choice", label: "set.maxAge", desc: "set.maxAge.desc",
      options: [{ value: "0", label: "opt.forever" }, { value: "1", label: "opt.day" }, { value: "7", label: "opt.week" },
                { value: "30", label: "opt.month" }, { value: "90", label: "opt.months3" }] },
    { key: "maxImageCacheMB", type: "choice", label: "set.imageCache", desc: "set.imageCache.desc",
      options: [{ value: "64", label: "64 MB" }, { value: "128", label: "128 MB" }, { value: "256", label: "256 MB" },
                { value: "512", label: "512 MB" }, { value: "1024", label: "1 GB" }] },
    { key: "maxHistoryMB", type: "choice", label: "set.historySize", desc: "set.historySize.desc",
      options: [{ value: "2", label: "2 MB" }, { value: "4", label: "4 MB" }, { value: "8", label: "8 MB" },
                { value: "16", label: "16 MB" }, { value: "32", label: "32 MB" }] },
    { section: "set.section.images" },
    { key: "ocr", type: "bool", label: "set.ocr", desc: "set.ocr.desc" },
    { key: "qrDecode", type: "bool", label: "set.qr", desc: "set.qr.desc" },
    { key: "ocrLang", type: "choice", label: "set.ocrLang", desc: "set.ocrLang.desc",
      options: [{ value: "eng", label: "opt.english" }, { value: "spa", label: "opt.spanish" }, { value: "eng+spa", label: "opt.both" }] },
    { section: "set.section.backup" },
    { key: "exportSnippets", type: "button", label: "set.exportSnippets", desc: "set.exportSnippets.desc", button: "opt.export" },
    { key: "importSnippets", type: "button", label: "set.importSnippets", desc: "set.importSnippets.desc", button: "opt.import" },
    { key: "exportSettings", type: "button", label: "set.exportSettings", desc: "set.exportSettings.desc", button: "opt.export" },
    { key: "importSettings", type: "button", label: "set.importSettings", desc: "set.importSettings.desc", button: "opt.import" }
  ]
  property int settingsCursor: 1 // índice en settingsRows (nunca un título)

  function openSettings() {
    root.cancelClearHistory()
    root.settingsCursor = root.nextSettingsRow(-1, 1)
    root.activeTab = "settings"
  }

  function closeSettings() {
    root.activeTab = "clipboard"
  }

  function settingValue(key) {
    return root.settings[key]
  }

  function nextSettingsRow(from, delta) {
    var i = from
    for (var n = 0; n < root.settingsRows.length; n++) {
      i += delta
      if (i < 0 || i >= root.settingsRows.length) return from
      if (!root.settingsRows[i].section) return i
    }
    return from
  }

  function moveSettingsCursor(delta) {
    root.settingsCursor = root.nextSettingsRow(root.settingsCursor, delta)
    settingsList.positionViewAtIndex(root.settingsCursor, ListView.Contain)
  }

  // Bool: alterna. Choice: avanza (delta 1) o retrocede (-1) sin dar la vuelta.
  function changeSetting(row, delta) {
    if (!row || row.section) return
    if (row.type === "button") { root.runBackup(row.key); return }
    if (row.type === "bool") {
      root.setSetting(row.key, !root.settingValue(row.key))
      return
    }
    var current = String(root.settingValue(row.key))
    var idx = -1
    for (var i = 0; i < row.options.length; i++) if (row.options[i].value === current) idx = i
    var next = idx < 0 ? 0 : Math.max(0, Math.min(row.options.length - 1, idx + delta))
    if (next !== idx) root.setChoice(row, row.options[next].value)
  }

  function setChoice(row, value) {
    root.setSetting(row.key, /^[0-9]+$/.test(value) ? Number(value) : String(value))
  }

  // ------------------------------------------------------------ snippets
  // Plantillas con nombre, slug y texto Markdown con {variables}; viven en su
  // propio archivo (snippets.json), fuera del historial y de sus límites.
  property var snippets: []
  property string snipQuery: ""
  property int snipIndex: 0
  readonly property var snipResults: Snippets.search(root.snippets, root.snipQuery)
  readonly property var currentSnippet: root.snipIndex >= 0 && root.snipIndex < root.snipResults.length ? root.snipResults[root.snipIndex] : null
  property bool snipEditing: false
  property string snipEditId: "" // "" = snippet nuevo
  property string pendingSnippetDeleteId: ""
  property string ignoreText: "" // lo que acabamos de pegar desde un snippet

  function saveSnippets() {
    snippetsFile.setText(Snippets.serialize(root.snippets))
  }

  function setSnipQuery(q) {
    root.snipQuery = q
    root.snipIndex = 0
  }

  function selectSnippet(delta) {
    var n = root.snipResults.length
    if (n === 0) return
    root.snipIndex = (root.snipIndex + delta + n) % n
    snipList.positionViewAtIndex(root.snipIndex, ListView.Contain)
  }

  function selectSnippetById(id) {
    for (var i = 0; i < root.snipResults.length; i++) {
      if (root.snipResults[i].id === id) { root.snipIndex = i; snipList.positionViewAtIndex(i, ListView.Contain); return }
    }
  }

  // Texto del último clip de texto, para la variable {clipboard}.
  function latestClipText() {
    for (var i = 0; i < root.history.length; i++) if (root.history[i].type === "text") return String(root.history[i].text || "")
    return ""
  }

  function renderSnippet(s) {
    return s ? Snippets.render(s.body, { now: new Date(), L: root.strings, clipboard: root.latestClipText() }) : ""
  }

  // Pega (o solo copia) el snippet con las variables resueltas.
  function pasteSnippet(s, copyOnly) {
    if (!s) return
    var text = root.renderSnippet(s)
    root.ignoreText = text
    root.close()
    root.closeQuick()
    root.writeClipboard(text, !copyOnly)
  }

  function newSnippet() {
    root.snipEditId = ""
    snipNameInput.text = ""
    snipSlugInput.text = ""
    snipBodyEdit.text = ""
    root.snipEditing = true
    Qt.callLater(function() { snipNameInput.forceActiveFocus() })
  }

  function editSnippet() {
    var s = root.currentSnippet
    if (!s) return
    root.snipEditId = s.id
    snipNameInput.text = s.name
    snipSlugInput.text = s.slug
    snipBodyEdit.text = s.body
    root.snipEditing = true
    Qt.callLater(function() {
      snipBodyEdit.forceActiveFocus()
      snipBodyEdit.cursorPosition = snipBodyEdit.length
    })
  }

  function saveSnippet() {
    if (!snipNameInput.text.trim() && !snipBodyEdit.text.trim()) { root.cancelSnippetEdit(); return }
    var r = Snippets.upsert(root.snippets, {
      id: root.snipEditId || undefined,
      name: snipNameInput.text,
      slug: snipSlugInput.text,
      body: snipBodyEdit.text
    }, Math.floor(Date.now() / 1000))
    root.snippets = r.list
    root.saveSnippets()
    root.snipEditing = false
    root.setSnipQuery("")
    root.selectSnippetById(r.id)
    keyCatcher.forceActiveFocus()
  }

  function cancelSnippetEdit() {
    root.snipEditing = false
    root.varsOpen = false
    keyCatcher.forceActiveFocus()
  }

  function requestDeleteSnippet() {
    var s = root.currentSnippet
    if (!s) return
    root.pendingSnippetDeleteId = s.id
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function confirmDeleteSnippet() {
    var id = root.pendingSnippetDeleteId
    root.pendingSnippetDeleteId = ""
    root.snippets = Snippets.remove(root.snippets, id)
    root.saveSnippets()
    root.cancelClearHistory()
    if (root.snipIndex >= root.snipResults.length) root.snipIndex = Math.max(0, root.snipResults.length - 1)
  }

  // Botones de Markdown del editor: envuelven la selección (o dejan el cursor
  // entre los marcadores si no hay selección).
  function wrapSelection(prefix, suffix) {
    var s = snipBodyEdit.selectionStart, e = snipBodyEdit.selectionEnd
    var sel = snipBodyEdit.getText(s, e)
    snipBodyEdit.remove(s, e)
    snipBodyEdit.insert(s, prefix + sel + suffix)
    if (sel) snipBodyEdit.select(s + prefix.length, s + prefix.length + sel.length)
    else snipBodyEdit.cursorPosition = s + prefix.length
    snipBodyEdit.forceActiveFocus()
  }

  function listifySelection() {
    var text = snipBodyEdit.text
    var s = snipBodyEdit.selectionStart, e = snipBodyEdit.selectionEnd
    var start = text.lastIndexOf("\n", s - 1) + 1
    var block = text.slice(start, e)
    var lines = block.split("\n").map(function(l) { return l.indexOf("- ") === 0 ? l : "- " + l })
    snipBodyEdit.remove(start, e)
    snipBodyEdit.insert(start, lines.join("\n"))
    snipBodyEdit.cursorPosition = start + lines.join("\n").length
    snipBodyEdit.forceActiveFocus()
  }

  function insertVariable(name) {
    var at = snipBodyEdit.cursorPosition
    snipBodyEdit.insert(at, "{" + name + "}")
    snipBodyEdit.cursorPosition = at + name.length + 2
    root.varsOpen = false
    snipBodyEdit.forceActiveFocus()
  }

  // ------------------------------------------------------------ popup rápido de snippets
  // Ventanita junto al mouse con solo buscador + lista: se abre con el atajo
  // global (Settings → Shortcuts), p. ej. Ctrl+Espacio estando en cualquier input.
  property bool quickOpen: false
  property string quickQuery: ""
  property int quickIndex: 0
  readonly property var quickResults: Snippets.search(root.snippets, root.quickQuery)
  property real quickX: 0
  property real quickY: 0
  readonly property int quickWidth: Style.space(440)
  readonly property int quickRowHeight: Style.space(32)
  readonly property int quickHeight: Style.space(54) + Math.max(1, Math.min(8, root.quickResults.length)) * root.quickRowHeight

  // IPC: omarchy-shell shell call leninzapata.super-clipboard-snippet quickSnippets '{}'
  function quickSnippets(payloadJson) {
    if (root.quickOpen) { root.closeQuick(); return "closed" }
    if (root.opened) root.close()
    root.quickQuery = ""
    root.quickIndex = 0
    quickInput.text = ""
    root.quickX = Math.max(0, (quickPanel.width - root.quickWidth) / 2)
    root.quickY = Math.max(0, (quickPanel.height - root.quickHeight) / 3)
    quickCursorProc.running = true
    root.quickOpen = true
    Qt.callLater(function() { quickInput.forceActiveFocus() })
    return "ok"
  }

  function closeQuick() {
    root.quickOpen = false
  }

  function placeQuick(raw) {
    var pos = null
    try { pos = JSON.parse(String(raw || "")) } catch (e) { pos = null }
    if (!pos) return
    var sx = quickPanel.screen ? quickPanel.screen.x : 0
    var sy = quickPanel.screen ? quickPanel.screen.y : 0
    var m = Style.space(12)
    root.quickX = Math.max(m, Math.min(quickPanel.width - root.quickWidth - m, Number(pos.x) - sx - Style.space(20)))
    root.quickY = Math.max(m, Math.min(quickPanel.height - root.quickHeight - m, Number(pos.y) - sy + Style.space(14)))
  }

  // ------------------------------------------------------------ variables (Ctrl+K)
  property bool varsOpen: false
  property int varsIndex: 0

  function openVars() {
    root.varsIndex = 0
    root.varsOpen = true
    Qt.callLater(function() { varsCatcher.forceActiveFocus() })
  }

  function closeVars() {
    root.varsOpen = false
    if (root.snipEditing) snipBodyEdit.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  // ------------------------------------------------------------ atajos globales
  // El plugin registra sus atajos en Hyprland en caliente (hyprctl eval), sin
  // escribir en bindings.lua: al arrancar, al cambiar el setting y tras cada
  // recarga de Hyprland (que borra lo registrado en caliente).
  property var appliedChords: []
  property bool shortcutsApplied: false

  function chordOf(id) {
    return String(id || "").split("+").map(function(k) { return k.trim().toUpperCase() }).join(" + ")
  }

  function applyShortcuts() {
    var lines = []
    var chords = []
    for (var i = 0; i < root.appliedChords.length; i++)
      lines.push('pcall(function() hl.unbind("' + root.appliedChords[i] + '") end)')
    var binds = [
      { id: root.settings.openShortcut, cmd: "omarchy-shell shell toggle leninzapata.super-clipboard-snippet" },
      { id: root.settings.quickShortcut, cmd: "omarchy-shell shell call leninzapata.super-clipboard-snippet quickSnippets '{}'" }
    ]
    for (var j = 0; j < binds.length; j++) {
      if (!binds[j].id) continue
      var chord = root.chordOf(binds[j].id)
      chords.push(chord)
      lines.push('pcall(function() hl.unbind("' + chord + '") end)')
      lines.push('hl.bind("' + chord + '", hl.dsp.exec_cmd("' + binds[j].cmd + '"), { description = "Super Clipboard-Snippet" })')
    }
    root.appliedChords = chords
    if (lines.length > 0) Quickshell.execDetached(["hyprctl", "eval", lines.join("; ")])
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") shortcutsTimer.restart()
    }
  }

  Timer {
    id: shortcutsTimer
    interval: 300
    repeat: false
    onTriggered: { root.appliedChords = []; root.applyShortcuts() }
  }

  Component.onDestruction: {
    var lines = root.appliedChords.map(function(c) { return 'pcall(function() hl.unbind("' + c + '") end)' })
    if (lines.length > 0) Quickshell.execDetached(["hyprctl", "eval", lines.join("; ")])
  }

  // ------------------------------------------------------------ copia de seguridad
  // Exportar: el selector de Omarchy elige carpeta y se escribe un JSON con
  // versión. Importar: se elige el archivo y se valida su "kind".
  property string backupAction: ""
  property string pendingImportKind: ""

  function runBackup(key) {
    root.backupAction = key
    var exporting = key.indexOf("export") === 0
    var picker = (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin/omarchy-file-select"
    pickerProc.command = exporting
      ? [picker, "--directory", "--title", root.t("backup.pickFolder")]
      : [picker, "--extensions", "json", "--title", root.t("backup.pickFile")]
    pickerProc.running = true
  }

  function notify(body) {
    Quickshell.execDetached(["notify-send", "-a", "Super Clipboard-Snippet", "Super Clipboard-Snippet", body])
  }

  function backupPicked(output) {
    var path = String(output || "").split("\n")[0].trim()
    if (!path) return
    var key = root.backupAction
    if (key.indexOf("export") === 0) {
      var kind = key === "exportSnippets" ? "snippets" : "settings"
      var d = new Date()
      var stamp = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
      var target = path.replace(/\/+$/, "") + "/super-clipboard-snippet-" + kind + "-" + stamp + ".json"
      var data = { app: "super-clipboard-snippet", kind: kind, version: 1, exportedAt: Math.floor(Date.now() / 1000) }
      if (kind === "snippets") data.snippets = root.snippets
      else data.settings = root.settings
      exportFile.path = target
      exportFile.setText(JSON.stringify(data, null, 1) + "\n")
      root.notify(root.t("backup.exported", { path: target }))
    } else {
      root.pendingImportKind = key === "importSnippets" ? "snippets" : "settings"
      importFile.path = ""
      importFile.path = path
    }
  }

  function importLoaded(raw) {
    var kind = root.pendingImportKind
    root.pendingImportKind = ""
    if (!kind) return
    var data = null
    try { data = JSON.parse(String(raw || "")) } catch (e) { data = null }
    var ok = data && data.app === "super-clipboard-snippet" && data.kind === kind
    if (!ok) { root.notify(root.t("backup.invalid", { kind: kind })); return }
    if (kind === "snippets") {
      var m = Snippets.merge(root.snippets, Array.isArray(data.snippets) ? data.snippets : [], Math.floor(Date.now() / 1000))
      root.snippets = m.list
      root.saveSnippets()
      root.notify(root.t("backup.imported", { added: m.added, updated: m.updated }))
    } else {
      var raw2 = Store.serializeSettings(data.settings || {})
      settingsFile.setText(raw2)
      root.applySettings(raw2)
      root.notify(root.t("backup.settingsImported"))
    }
  }

  // ------------------------------------------------------------ tabs

  function tabIndex(key) {
    for (var i = 0; i < root.tabs.length; i++) if (root.tabs[i].key === key) return i
    return 0
  }

  // Sin vuelta circular: en la primera pestaña ← no hace nada, en la última → tampoco.
  function moveTab(delta) {
    var next = Math.max(0, Math.min(root.tabs.length - 1, root.tabIndex(root.activeTab) + delta))
    root.setTab(root.tabs[next].key)
  }

  function moveChip(delta) {
    var idx = 0
    for (var i = 0; i < root.typeChips.length; i++) if (root.typeChips[i].key === root.typeFilter) idx = i
    var next = Math.max(0, Math.min(root.typeChips.length - 1, idx + delta))
    if (next !== idx) root.setTypeFilter(root.typeChips[next].key)
  }

  function setTab(key) {
    root.chipMode = false
    if (key === root.activeTab) return
    root.cancelClearHistory()
    root.activeTab = key
  }

  // ------------------------------------------------------------ pause
  // Toggle via IPC:  omarchy-shell shell call leninzapata.super-clipboard-snippet pause '{"paused":true}'
  // (or {"paused":false}, or {"paused":"toggle"}), and Ctrl+Space in the picker.
  function setPaused(next) {
    root.paused = !!next
    pausedFile.setText(JSON.stringify({ paused: root.paused }) + "\n")
  }

  function pause(payloadJson) {
    var p = null
    try { p = JSON.parse(String(payloadJson || "{}")) } catch (e) { p = null }
    var next = p && typeof p.paused !== "undefined"
      ? (p.paused === "toggle" ? !root.paused : !!p.paused)
      : !root.paused
    root.setPaused(next)
    Quickshell.execDetached(["notify-send", "-a", "Super Clipboard-Snippet",
      root.t(next ? "notify.paused" : "notify.resumed"),
      root.t(next ? "notify.pausedBody" : "notify.resumedBody")])
    return JSON.stringify({ paused: root.paused })
  }

  function isPaused() { return JSON.stringify({ paused: root.paused }) }

  // Screenshot helper: omarchy-shell shell call leninzapata.super-clipboard-snippet debugSetFilter '{"text":"…"}'
  // Opens the picker with a preset query so scripts can capture it keyboard-free.
  function debugSetFilter(payloadJson) {
    var p = {}
    try { p = JSON.parse(String(payloadJson || "{}")) } catch (e) { p = {} }
    root.open()
    root.setFilter(String(p.text || ""))
    return "ok"
  }

  // ------------------------------------------------------------ store

  function loadHistory(raw) {
    root.history = Store.parseHistory(raw, Math.floor(Date.now() / 1000))
    root.typeCache = {}
    root.applyRetentionPolicy()
    root.checkDeps()
    if (root.opened) root.rebuild()
  }

  // Cantidad, antigüedad y peso (settings). Devuelve las imágenes que sobran.
  function enforceLimits() {
    var pruned = Store.prune(root.history, root.historyLimit)
    var aged = Store.pruneByAge(pruned.entries, root.maxAgeDays > 0 ? root.maxAgeDays * 86400 : -1, Math.floor(Date.now() / 1000))
    var sized = Store.pruneBySize(aged.entries, root.settings.maxImageCacheMB * 1048576, root.settings.maxHistoryMB * 1048576)
    root.history = sized.entries
    return pruned.droppedImagePaths.concat(aged.droppedImagePaths, sized.droppedImagePaths)
  }

  function saveHistory() {
    var paths = root.enforceLimits()
    historyFile.setText(JSON.stringify(root.history, null, 1) + "\n")
    if (paths.length > 0) queueGc(paths)
  }

  // Pasada completa al cargar el historial y al cambiar los settings: solo
  // reescribe el archivo si algún límite quitó algo.
  function applyRetentionPolicy() {
    var before = root.history.length
    var paths = root.enforceLimits()
    if (root.history.length === before) return
    if (paths.length > 0) queueGc(paths)
    historyFile.setText(JSON.stringify(root.history, null, 1) + "\n")
  }

  // Serialize GC batches: a single reusable Process would silently drop
  // overlapping runs, so pending paths queue until the current rm exits.
  property var gcQueue: []
  function queueGc(paths) {
    root.gcQueue.push(paths)
    if (!gcProc.running) runNextGc()
  }
  function runNextGc() {
    if (root.gcQueue.length === 0) return
    gcProc.command = ["rm", "-f"].concat(root.gcQueue.shift())
    gcProc.running = true
  }

  function addClipboardJson(line) {
    if (root.paused) return
    var entry = null
    try { entry = JSON.parse(String(line || "")) } catch (e) { return }
    if (!entry) return
    // Un snippet pegado pasa por el portapapeles: no se guarda como clip.
    if (root.ignoreText && entry.type === "text" && String(entry.text) === root.ignoreText) {
      root.ignoreText = ""
      return
    }
    root.history = Store.addEntry(root.history, entry, Math.floor(Date.now() / 1000))
    root.saveHistory()
    if (root.opened) root.rebuild()
  }

  // ------------------------------------------------------------ search

  function effectiveQuery() {
    var q = root.filterText
    if (root.typeFilter === "pinned") return q + (q ? " " : "") + "is:pinned"
    if (root.typeFilter) return "type:" + root.typeFilter + (q ? " " + q : "")
    return q
  }

  function rebuild() {
    var now = Math.floor(Date.now() / 1000)
    var rows = []
    for (var i = 0; i < root.history.length; i++) {
      var entry = root.history[i]
      var derived = root.typeCache[entry.id]
      if (derived === undefined) {
        derived = Classify.deriveType(entry)
        root.typeCache[entry.id] = derived
      }
      rows.push(Store.buildRow(entry, derived, now))
    }
    root.pinIds = Store.pinOrder(root.history)
    var grouped = Store.groupPinned(Fuzzy.searchRows(rows, root.effectiveQuery(), now, root.displayLimit), root.pinIds)
    root.pinnedShown = grouped.pinnedCount
    root.results = grouped.results

    if (root.results.length === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= root.results.length) root.selectedIndex = root.results.length - 1

    Qt.callLater(function() {
      if (root.results.length > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuild()
  }

  // Desliza la tira de filtros para que el activo quede a la vista.
  function ensureChipVisible() {
    var idx = 0
    for (var i = 0; i < root.typeChips.length; i++) if (root.typeChips[i].key === root.typeFilter) idx = i
    var item = chipsRepeater.itemAt(idx)
    if (!item) return
    var pad = Style.space(18)
    var maxX = Math.max(0, chipsFlick.contentWidth - chipsFlick.width)
    if (item.x - pad < chipsFlick.contentX) chipsFlick.contentX = Math.max(0, item.x - pad)
    else if (item.x + item.width + pad > chipsFlick.contentX + chipsFlick.width)
      chipsFlick.contentX = Math.min(maxX, item.x + item.width + pad - chipsFlick.width)
  }

  function setTypeFilter(next) {
    root.typeFilter = next
    Qt.callLater(root.ensureChipVisible)
    root.selectedIndex = 0
    root.disarmPointer()
    root.rebuild()
  }

  // ------------------------------------------------------------ navigation

  function select(delta) {
    if (root.results.length === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? root.results.length - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + root.results.length) % root.results.length
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (root.results.length === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, root.results.length - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  // ------------------------------------------------------------ actions

  function pasteResult(result) {
    if (!result) return
    root.close()
    root.history = Store.touch(root.history, result.row.entry.id, Math.floor(Date.now() / 1000))
    root.saveHistory()
    Quickshell.execDetached([root.pluginDir + "/paste-entry.sh", result.row.entry.id])
  }

  function copyResult(result) {
    if (!result) return
    root.close()
    Quickshell.execDetached([root.pluginDir + "/paste-entry.sh", result.row.entry.id, "--copy-only"])
  }

  function openResult(result) {
    if (!result) return
    root.close()
    Quickshell.execDetached([root.pluginDir + "/open-entry.sh", result.row.entry.id])
  }

  // Text content of an entry as a string: the text itself, or for images the
  // recognized (OCR) text, falling back to a decoded QR payload.
  function textContent(result) {
    if (!result) return ""
    var e = result.row.entry
    if (e.type === "image") return String(e.ocr || e.qr || "")
    return String(e.text || "")
  }

  // Copy a plain string (not an entry) to the clipboard and close.
  function copyText(text) {
    if (!text) return
    root.close()
    root.writeClipboard(text, false)
  }

  // Pone un texto en el portapapeles (y opcionalmente lo pega) pasándolo por
  // stdin, nunca como argumento: wl-copy se queda en segundo plano mientras es
  // dueño de la selección, y sus argumentos los puede leer cualquier usuario.
  function writeClipboard(text, thenPaste) {
    var script = thenPaste ? "wl-copy --type text/plain; sleep 0.15; wtype -M shift -k Insert -m shift"
                           : "wl-copy --type text/plain"
    var writer = clipWriterComponent.createObject(root, { payload: String(text), command: ["sh", "-c", script] })
    writer.running = true
  }

  Component {
    id: clipWriterComponent
    Process {
      property string payload: ""
      stdinEnabled: true
      onStarted: {
        write(payload)
        payload = ""
        stdinEnabled = false // cierra stdin: wl-copy recibe EOF
      }
      onExited: destroy()
    }
  }

  function removeIndex(index) {
    if (index < 0 || index >= root.results.length) return
    var entry = root.results[index].row.entry
    root.history = Store.removeById(root.history, entry.id)
    delete root.typeCache[entry.id]
    root.saveHistory()
    if (root.results.length <= 1) root.selectedIndex = 0
    else if (root.selectedIndex >= root.results.length - 1) root.selectedIndex = root.results.length - 2
    root.rebuild()
  }

  function togglePinIndex(index) {
    if (index < 0 || index >= root.results.length) return
    var id = root.results[index].row.entry.id
    root.history = Store.togglePin(root.history, id, Math.floor(Date.now() / 1000))
    root.saveHistory()
    root.rebuild()
    for (var i = 0; i < root.results.length; i++) {
      if (root.results[i].row.entry.id === id) { root.selectAbsolute(i); break }
    }
  }

  // Ctrl+N pega el pin N (1-based) aunque una búsqueda lo esté ocultando:
  // el número es del pin, no de la fila visible.
  function pastePin(number) {
    var id = root.pinIds[number - 1]
    if (!id) return
    var entry = Store.findById(root.history, id)
    if (entry) root.pasteResult({ row: { entry: entry } })
  }

  function pinNumber(id) {
    var n = root.pinIds.indexOf(id)
    return n >= 0 ? n + 1 : 0
  }

  // Un solo diálogo de confirmación para dos usos: vaciar el historial o
  // borrar un clip (este último solo si el setting confirmDelete está activo).
  property string pendingDeleteId: ""

  // Vaciar es irreversible: además de confirmar hay que escribir "delete"
  // (diálogo propio, clearPrompt). El ConfirmDialog queda para borrar un clip.
  property bool clearPromptOpen: false
  readonly property string clearWord: root.t("clear.word")

  function requestClearHistory() {
    if (root.history.length === root.pinIds.length) return // solo hay pines
    root.cancelEdit()
    clearInput.text = ""
    root.clearPromptOpen = true
    Qt.callLater(function() { clearInput.forceActiveFocus() })
  }

  function clearWordTyped() {
    return clearInput.text.trim().toLowerCase() === root.clearWord
  }

  // ------------------------------------------------------------ actions (Ctrl+.)
  // Menú de lo que se puede hacer con el clip seleccionado; cambia según su
  // tipo (Actions.listFor). Se filtra escribiendo; ↑↓ Enter Esc.
  property bool actionsOpen: false
  property var actionItems: [] // [{ id, icon, label }]
  property string actionsQuery: ""
  property int actionCursor: 0
  readonly property var visibleActions: root.actionItems.filter(function(a) { return Actions.matches(a.label, root.actionsQuery) })

  function openActions() {
    var r = root.currentResult
    if (!r) return
    root.chipMode = false
    root.cancelEdit()
    var ids = Actions.listFor(r.row.entry, r.row.type)
    var items = []
    for (var i = 0; i < ids.length; i++) items.push({ id: ids[i], icon: Actions.ICONS[ids[i]] || "", label: root.t("action." + ids[i]) })
    root.actionItems = items
    actionsFilter.text = ""
    root.actionCursor = 0
    root.actionsOpen = true
    Qt.callLater(function() { actionsFilter.forceActiveFocus() })
  }

  function closeActions() {
    root.actionsOpen = false
    keyCatcher.forceActiveFocus()
  }

  function moveActionCursor(delta) {
    var n = root.visibleActions.length
    if (n === 0) return
    root.actionCursor = (root.actionCursor + delta + n) % n
    actionsList.positionViewAtIndex(root.actionCursor, ListView.Contain)
  }

  function hex2(n) { var s = Number(n).toString(16); return s.length < 2 ? "0" + s : s }

  function runAction(id) {
    var r = root.currentResult
    root.closeActions()
    if (!r) return
    var e = r.row.entry
    var text = String(e.text || "")
    if (Actions.isTransform(id)) {
      var out = Actions.transform(id, text)
      if (out === null) return
      root.startEdit()
      editor.text = out // borrador: Ctrl+Enter lo guarda, Esc lo descarta
      return
    }
    switch (id) {
    case "paste": root.pasteResult(r); break
    case "copy": root.copyResult(r); break
    case "edit": root.startEdit(); break
    case "note": root.startNote(); break
    case "pin": case "unpin": root.togglePinIndex(root.selectedIndex); break
    case "delete": root.requestRemoveIndex(root.selectedIndex); break
    case "open": case "openLink": root.openResult(r); break
    case "copyDomain": root.copyText(Classify.urlDomain(Classify.extractUrl(text) || text.trim())); break
    case "copyHex":
      var rgb = Classify.colorToRgb(text.trim())
      if (rgb) root.copyText("#" + root.hex2(rgb[0]) + root.hex2(rgb[1]) + root.hex2(rgb[2]))
      break
    case "copyRgb":
      var c = Classify.colorToRgb(text.trim())
      if (c) root.copyText("rgb(" + c[0] + ", " + c[1] + ", " + c[2] + ")")
      break
    case "copyHsl":
      var h = Classify.colorToHsl(text.trim())
      if (h) root.copyText("hsl(" + h[0] + ", " + h[1] + "%, " + h[2] + "%)")
      break
    case "copyOcr": root.copyText(String(e.ocr || "")); break
    case "copyQr": root.copyText(String(e.qr || "")); break
    case "copyPath": root.copyText(String(e.path || "")); break
    case "copyPaths": root.copyText((e.paths || []).join("\n")); break
    }
  }

  // ------------------------------------------------------------ edit (F2 / Ctrl+E) y nota (Ctrl+M)
  // Mismo editor, en el sitio del preview; Ctrl+Enter / Ctrl+S guarda, Esc
  // cancela. Texto: solo clips de texto, y el clip cambia de id (sale del
  // contenido). Nota: cualquier clip; vacía = sin nota.
  property bool editing: false
  property string editingId: ""
  property string editMode: "text" // "text" | "note"

  function startNote() {
    var r = root.currentResult
    if (!r) return
    root.chipMode = false
    root.editMode = "note"
    root.editingId = r.row.entry.id
    editor.text = String(r.row.entry.note || "")
    root.editing = true
    Qt.callLater(function() {
      editor.forceActiveFocus()
      editor.cursorPosition = editor.length
    })
  }

  function startEdit() {
    var r = root.currentResult
    if (!r || r.row.entry.type !== "text") return
    root.chipMode = false
    root.editMode = "text"
    root.editingId = r.row.entry.id
    editor.text = String(r.row.entry.text || "")
    root.editing = true
    Qt.callLater(function() {
      editor.forceActiveFocus()
      editor.cursorPosition = editor.length
    })
  }

  function saveEdit() {
    if (!root.editing) return
    if (root.editMode === "note") {
      var noteId = root.editingId
      root.history = Store.setNote(root.history, noteId, editor.text)
      root.editing = false
      root.editingId = ""
      root.saveHistory()
      root.rebuild()
      for (var j = 0; j < root.results.length; j++) {
        if (root.results[j].row.entry.id === noteId) { root.selectAbsolute(j); break }
      }
      keyCatcher.forceActiveFocus()
      return
    }
    var oldId = root.editingId
    var r = Store.updateText(root.history, oldId, editor.text, Math.floor(Date.now() / 1000))
    root.editing = false
    root.editingId = ""
    if (r.id !== oldId) {
      root.history = r.history
      delete root.typeCache[oldId]
      root.saveHistory()
      root.rebuild()
      for (var i = 0; i < root.results.length; i++) {
        if (root.results[i].row.entry.id === r.id) { root.selectAbsolute(i); break }
      }
    }
    keyCatcher.forceActiveFocus()
  }

  function cancelEdit() {
    if (!root.editing) return
    root.editing = false
    root.editingId = ""
    keyCatcher.forceActiveFocus()
  }

  function requestRemoveIndex(index) {
    if (index < 0 || index >= root.results.length) return
    if (!root.settings.confirmDelete) {
      root.removeIndex(index)
      return
    }
    root.pendingDeleteId = root.results[index].row.entry.id
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function confirmRemove() {
    var id = root.pendingDeleteId
    root.pendingDeleteId = ""
    root.cancelClearHistory()
    for (var i = 0; i < root.results.length; i++) {
      if (root.results[i].row.entry.id === id) { root.removeIndex(i); return }
    }
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.pendingSnippetDeleteId = ""
    root.clearPromptOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Vacía el historial pero deja los pines: son el grupo fijo de arriba.
  function confirmClearHistory() {
    var dropped = []
    var kept = []
    for (var i = 0; i < root.history.length; i++) {
      var e = root.history[i]
      if (e.pinned) kept.push(e)
      else if (e.type === "image" && e.path) dropped.push(e.path)
    }
    root.clearPromptOpen = false
    root.history = kept
    root.typeCache = {}
    root.saveHistory()
    if (dropped.length > 0) queueGc(dropped)
    root.selectedIndex = 0
    root.clearConfirmOpen = false
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: initProc.running = true

  // ------------------------------------------------------------ capture

  ListModel { id: displayModel }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  // Settings propios (no shell.json): los escribe la página de Settings del
  // panel y se recargan solos si alguien edita el archivo a mano.
  FileView {
    id: settingsFile
    path: root.configDir + "/settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("{}")
    onFileChanged: reload()
  }

  function setSetting(key, value) {
    var next = {}
    for (var k in root.settings) next[k] = root.settings[k]
    next[key] = value
    var raw = Store.serializeSettings(next)
    settingsFile.setText(raw)
    root.applySettings(raw)
  }

  // Missing-helper state surfaced IN the picker: banner with the exact
  // command and a "Run in terminal" button. Nothing launches on its own.
  property bool depsChecked: false
  property var missingDeps: [] // [{ name, packages }]
  function checkDeps() {
    if (root.depsChecked || depsProc.running) return
    root.depsChecked = true
    var checks = [
      "python3|dep.capture|python3",
      "jq|dep.actions|jq",
      "wl-copy|dep.access|wl-clipboard",
      "wtype|dep.paste|wtype"
    ]
    if (root.qrDecode) checks.push("zbarimg|dep.qr|zbar")
    if (root.ocr) checks.push("tesseract|dep.ocr|tesseract tesseract-data-eng")
    var script = ""
    for (var i = 0; i < checks.length; i++) {
      var fields = checks[i].split("|")
      script += "command -v " + fields[0] + " >/dev/null 2>&1 || printf '%s\\n' '" + checks[i] + "';"
    }
    depsProc.command = ["bash", "-c", script]
    depsProc.running = true
  }

  function depResult(output) {
    var missing = []
    var lines = String(output || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var fields = lines[i].split("|")
      if (fields.length === 3)
        missing.push({ name: fields[1], packages: fields[2] })
    }
    root.missingDeps = missing
  }

  function missingDependencyCommand() {
    var packages = []
    for (var i = 0; i < root.missingDeps.length; i++) {
      var names = root.missingDeps[i].packages.split(" ")
      for (var j = 0; j < names.length; j++)
        if (packages.indexOf(names[j]) === -1) packages.push(names[j])
    }
    return packages.length ? "omarchy pkg add " + packages.join(" ") : ""
  }

  function applySettings(raw) {
    var s = Store.parseSettings(raw)
    var shortcutsChanged = s.openShortcut !== root.settings.openShortcut || s.quickShortcut !== root.settings.quickShortcut
    root.settings = s
    if (shortcutsChanged || !root.shortcutsApplied) { root.shortcutsApplied = true; root.applyShortcuts() }
    var needsWatchRestart = s.qrDecode !== root.qrDecode || s.ocr !== root.ocr
      || s.ocrLang !== root.ocrLang
    root.historyLimit = s.historyLimit
    root.maxAgeDays = s.maxAgeDays
    root.displayLimit = s.maxRows
    root.qrDecode = s.qrDecode
    root.ocr = s.ocr
    root.ocrLang = s.ocrLang
    // The watchers read qr/ocr settings from the environment — restart them
    // so changes take effect without a shell reload.
    if (needsWatchRestart && watchProc.running) {
      watchProc.running = false
      watchRestartTimer.restart()
    }
    root.applyRetentionPolicy()
    root.checkDeps()
    if (root.opened) root.rebuild()
  }

  // Pause state survives shell restarts.
  FileView {
    id: pausedFile
    path: root.stateDir + "/paused.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.paused = !!JSON.parse(text()).paused } catch (e) { root.paused = false }
    }
    onLoadFailed: root.paused = false
  }

  FileView {
    id: snippetsFile
    path: root.stateDir + "/snippets.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.snippets = Snippets.parseList(text(), Math.floor(Date.now() / 1000))
    onLoadFailed: root.snippets = []
    onFileChanged: reload()
  }

  FileView {
    id: historyFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  Process {
    id: pickerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backupPicked(text)
    }
  }

  FileView {
    id: exportFile
    printErrors: false
    atomicWrites: true
  }

  FileView {
    id: importFile
    printErrors: false
    onLoaded: root.importLoaded(text())
  }

  Process {
    id: quickCursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.placeQuick(text)
    }
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.placeAtCursor(text)
    }
  }

  Process {
    id: depsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.depResult(text)
    }
  }
  Process {
    id: gcProc
    onExited: runNextGc()
  }

  // Reap watchers left behind by a previous shell instance, then start our
  // own. pdeathsig kills them whenever the shell exits.
  Process {
    id: initProc
    command: ["sh", "-c", 'mkdir -p "$1" "$3"; pkill -f "wl-paste --watch python3 $2/capture[.]py" || true',
              "init", root.stateDir, root.pluginDir, root.configDir]
    onExited: {
      snapshotProc.running = true
      watchProc.running = true
    }
  }

  Process {
    id: snapshotProc
    command: ["python3", root.pluginDir + "/capture.py"]
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: watchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", "python3", root.pluginDir + "/capture.py", "watch"]
    environment: ({
      "CLIPBOARD_QR": root.qrDecode ? "1" : "0",
      "CLIPBOARD_OCR": root.ocr ? "1" : "0",
      "CLIPBOARD_OCR_LANG": root.ocrLang
    })
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  // Cursor blink
  Timer {
    running: root.opened
    interval: 530
    repeat: true
    onTriggered: root.cursorVisible = !root.cursorVisible
  }

  // ------------------------------------------------------------ window

  // Popup rápido de snippets: ventana propia, transparente, con una tarjeta
  // chica junto al mouse. Un clic fuera la cierra siempre.
  PanelWindow {
    id: quickPanel
    visible: root.quickOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.quickOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: root.closeQuick() }

    BorderSurface {
      id: quickCard
      x: root.quickX
      y: root.quickY
      width: root.quickWidth
      height: root.quickHeight
      radius: 0
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.space(8)

      MouseArea { anchors.fill: parent; onClicked: quickInput.forceActiveFocus() }

      Item {
        id: quickHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(10)
        height: Style.space(32)

        Text {
          id: quickIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅴"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        TextInput {
          id: quickInput
          anchors.left: quickIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          onTextChanged: {
            root.quickQuery = text
            root.quickIndex = 0
          }

          Keys.onPressed: function(event) {
            var n = root.quickResults.length
            if (event.key === Qt.Key_Escape) {
              root.closeQuick()
              event.accepted = true
            } else if (event.key === Qt.Key_Up && n > 0) {
              root.quickIndex = (root.quickIndex - 1 + n) % n
              quickList.positionViewAtIndex(root.quickIndex, ListView.Contain)
              event.accepted = true
            } else if (event.key === Qt.Key_Down && n > 0) {
              root.quickIndex = (root.quickIndex + 1) % n
              quickList.positionViewAtIndex(root.quickIndex, ListView.Contain)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.pasteSnippet(root.quickResults[root.quickIndex], (event.modifiers & Qt.ShiftModifier) !== 0)
              event.accepted = true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: quickInput.text.length === 0
            text: root.t("quick.placeholder")
            color: root.mutedFg
            opacity: 0.6
            font: quickInput.font
          }
        }
      }

      Rectangle {
        id: quickLine
        anchors.top: quickHeader.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: root.lineColor
      }

      ListView {
        id: quickList
        anchors.top: quickLine.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(4)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.quickResults

        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool current: index === root.quickIndex
          width: quickList.width
          height: root.quickRowHeight
          radius: Style.space(4)
          color: current ? root.selectedBackground : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: quickSlug.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.name || parent.modelData.slug
            color: parent.current ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: quickSlug
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.45)
            text: parent.modelData.slug
            color: root.rowMetaFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideLeft
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.quickIndex = parent.index
            onClicked: root.pasteSnippet(parent.modelData, false)
          }
        }
      }

      Text {
        anchors.centerIn: quickList
        visible: root.quickResults.length === 0
        text: root.t("quick.empty")
        color: root.mutedFg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Una sola ventana a pantalla completa: fondo oscurecido + tarjeta centrada
  // (como el image-picker de Omarchy). Con dos ventanas, la del fondo en la
  // capa Top no recibía el ratón y el clic atravesaba hasta la ventana de detrás.
  // Sigue visible durante el fade de salida, pero suelta el teclado al instante
  // para que el pegado llegue a la ventana de detrás.
  PanelWindow {
    id: panel
    visible: root.surfaceVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.scrimAlpha * root.reveal)
    }

    // Clic fuera de la tarjeta: nunca llega a la ventana de detrás; cierra solo
    // si el setting closeOnClickOutside está activo.
    MouseArea {
      anchors.fill: parent
      onClicked: if (root.settings.closeOnClickOutside) root.close()
    }

    BorderSurface {
      id: card
      anchors.centerIn: root.atCursor ? undefined : parent
      x: root.cardX
      y: root.cardY
      width: root.cardWidth
      height: root.cardHeight
      opacity: root.reveal
      scale: 0.97 + 0.03 * root.reveal
      radius: 0 // esquinas rectas
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.chipMode = false }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          if (ctrl && event.key === Qt.Key_Comma) {
            if (root.activeTab === "settings") root.closeSettings()
            else root.openSettings()
            event.accepted = true
            return
          }

          // Pausar/reanudar la captura desde cualquier vista.
          if (ctrl && event.key === Qt.Key_Equal) {
            root.pause(JSON.stringify({ paused: "toggle" }))
            event.accepted = true
            return
          }

          if (root.activeTab === "settings") {
            var row = root.settingsRows[root.settingsCursor]
            if (event.key === Qt.Key_Escape) root.closeSettings()
            else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) root.moveSettingsCursor(-1)
            else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) root.moveSettingsCursor(1)
            else if (event.key === Qt.Key_Left) root.changeSetting(row, -1)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Space
                     || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.changeSetting(row, 1)
            event.accepted = true
            return
          }

          if (root.activeTab === "clipboard" && ctrl && event.key === Qt.Key_F) {
            root.chipMode = !root.chipMode
            event.accepted = true
            return
          }

          if (root.chipMode) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
              root.moveChip(event.key === Qt.Key_Left ? -1 : 1)
              event.accepted = true
              return
            }
            // Cualquier otra tecla sale del modo; Esc / Enter solo salen.
            root.chipMode = false
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              event.accepted = true
              return
            }
          }

          // El buscador no tiene cursor movible, así que ← / → quedan libres
          // para cambiar de pestaña en cualquier momento.
          var bareArrow = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier))
          if (bareArrow && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            root.moveTab(event.key === Qt.Key_Left ? -1 : 1)
            event.accepted = true
            return
          }

          if (root.activeTab === "snippets") {
            if (event.key === Qt.Key_Escape) {
              if (root.snipQuery) root.setSnipQuery("")
              else root.close()
            } else if (ctrl && event.key === Qt.Key_N) {
              root.newSnippet()
            } else if (event.key === Qt.Key_F2 || (ctrl && event.key === Qt.Key_E)) {
              root.editSnippet()
            } else if (ctrl && event.key === Qt.Key_K) {
              root.openVars()
            } else if (event.key === Qt.Key_Delete) {
              root.requestDeleteSnippet()
            } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
              root.selectSnippet(-1)
            } else if (event.key === Qt.Key_Down) {
              root.selectSnippet(1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.pasteSnippet(root.currentSnippet, (event.modifiers & Qt.ShiftModifier) !== 0)
            } else if (Util.editsFilter(event, root.snipQuery)) {
              root.setSnipQuery(Util.editedFilter(event, root.snipQuery))
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && !ctrl) {
              root.setSnipQuery(root.snipQuery + event.text)
            }
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.typeFilter) root.setTypeFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
            else root.requestRemoveIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-8)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(8)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(root.results.length - 1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.pastePin(event.key - Qt.Key_0)
            event.accepted = true
          } else if (event.key === Qt.Key_F2 || (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier))) {
            root.startEdit()
            event.accepted = true
          } else if (event.key === Qt.Key_M && (event.modifiers & Qt.ControlModifier)) {
            root.startNote()
            event.accepted = true
          } else if (event.key === Qt.Key_Period && (event.modifiers & Qt.ControlModifier)) {
            root.openActions()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.togglePinIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) {
            root.openResult(root.currentResult)
            event.accepted = true
          } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            root.copyText(root.textContent(root.currentResult))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ShiftModifier) root.copyResult(root.currentResult)
            else if (event.modifiers & Qt.AltModifier) root.openResult(root.currentResult)
            else root.pasteResult(root.currentResult)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: root.t(root.pendingSnippetDeleteId ? "confirm.deleteSnippet" : "confirm.deleteClip")
          confirmText: root.t("confirm.delete")
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.pendingSnippetDeleteId ? root.confirmDeleteSnippet() : root.confirmRemove()
        }
      }

      // Variables (Ctrl+K): catálogo con descripción y ejemplo en el idioma
      // actual; Enter inserta en el editor de snippet.
      Item {
        anchors.fill: parent
        z: 26
        visible: root.varsOpen

        Rectangle { anchors.fill: parent; color: root.scrim }
        MouseArea { anchors.fill: parent; onClicked: root.closeVars() }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(Style.space(560), parent.width - Style.space(60))
          height: Math.min(varsTitle.height + Snippets.VARIABLES.length * Style.space(34) + Style.space(70), parent.height - Style.space(60))
          radius: root.cornerRadius
          color: root.background
          border.width: 1
          border.color: Util.alpha(root.accent, 0.5)

          MouseArea { anchors.fill: parent; onClicked: varsCatcher.forceActiveFocus() }

          Item {
            id: varsCatcher
            anchors.fill: parent
            focus: root.varsOpen
            Keys.onPressed: function(event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              var n = Snippets.VARIABLES.length
              if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_K)) root.closeVars()
              else if (event.key === Qt.Key_Up) root.varsIndex = (root.varsIndex - 1 + n) % n
              else if (event.key === Qt.Key_Down) root.varsIndex = (root.varsIndex + 1) % n
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.snipEditing) root.insertVariable(Snippets.VARIABLES[root.varsIndex])
                else root.closeVars()
              }
              varsList.positionViewAtIndex(root.varsIndex, ListView.Contain)
              event.accepted = true
            }
          }

          Text {
            id: varsTitle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Style.space(16)
            text: "󰘦  " + root.t("vars.title")
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          ListView {
            id: varsList
            anchors.top: varsTitle.bottom
            anchors.topMargin: Style.space(10)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: varsHint.top
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.bottomMargin: Style.space(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Snippets.VARIABLES

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool current: index === root.varsIndex
              width: varsList.width
              height: Style.space(34)
              radius: Style.space(4)
              color: current ? root.selectedBackground : "transparent"

              Text {
                id: varToken
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(150)
                text: "{" + parent.modelData + "}"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.left: varToken.right
                anchors.right: varExample.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("var." + parent.modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: varExample
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.space(220))
                text: Snippets.render("{" + parent.modelData + "}", { now: new Date(), L: root.strings, clipboard: root.latestClipText() }).replace(/\n/g, " ")
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.varsIndex = parent.index
                onClicked: {
                  if (root.snipEditing) root.insertVariable(parent.modelData)
                  else root.closeVars()
                }
              }
            }
          }

          Text {
            id: varsHint
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Style.space(16)
            text: root.t(root.snipEditing ? "vars.insertHint" : "vars.readHint")
            color: root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Menú de acciones (Ctrl+.): sobre el preview, con filtro.
      Item {
        anchors.fill: parent
        z: 25
        visible: root.actionsOpen

        MouseArea { anchors.fill: parent; onClicked: root.closeActions() }

        Rectangle {
          id: actionsBox
          anchors.right: parent.right
          anchors.rightMargin: root.contentMargin + Style.space(12)
          anchors.top: parent.top
          anchors.topMargin: Style.space(140)
          width: Style.space(360)
          height: Math.min(actionsHeader.height + Math.max(1, root.visibleActions.length) * Style.space(32) + Style.space(14),
                           parent.height - Style.space(190))
          radius: root.cornerRadius
          color: root.background
          border.width: 1
          border.color: Util.alpha(root.accent, 0.5)

          MouseArea { anchors.fill: parent; onClicked: actionsFilter.forceActiveFocus() }

          Item {
            id: actionsHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(40)

            Text {
              id: actionsTitle
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰇘  " + root.t("actions.title")
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            TextInput {
              id: actionsFilter
              anchors.left: actionsTitle.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: {
                root.actionsQuery = text
                root.actionCursor = 0
              }

              Keys.onPressed: function(event) {
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_Period)) {
                  root.closeActions()
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                  root.moveActionCursor(-1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                  root.moveActionCursor(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  var a = root.visibleActions[root.actionCursor]
                  if (a) root.runAction(a.id)
                  event.accepted = true
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: actionsFilter.text.length === 0
                text: root.t("actions.filter")
                color: root.mutedFg
                opacity: 0.6
                font: actionsFilter.font
              }
            }

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 1
              color: root.lineColor
            }
          }

          ListView {
            id: actionsList
            anchors.top: actionsHeader.bottom
            anchors.topMargin: Style.space(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleActions

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool current: index === root.actionCursor
              width: actionsList.width
              height: Style.space(32)
              radius: Style.space(4)
              color: current ? root.selectedBackground : "transparent"

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  width: Style.space(18)
                  text: parent.parent.modelData.icon
                  color: parent.parent.modelData.id === "delete" ? root.pausedColor : root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: parent.parent.modelData.label
                  color: parent.parent.modelData.id === "delete" ? root.pausedColor
                       : parent.parent.current ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.actionCursor = parent.index
                onClicked: root.runAction(parent.modelData.id)
              }
            }
          }

          Text {
            anchors.centerIn: actionsList
            visible: root.visibleActions.length === 0
            text: root.t("actions.none")
            color: root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Vaciar historial: hay que escribir "delete" para habilitar el botón.
      Item {
        anchors.fill: parent
        z: 30
        visible: root.clearPromptOpen

        Rectangle {
          anchors.fill: parent
          color: root.scrim
        }

        MouseArea { anchors.fill: parent; onClicked: root.cancelClearHistory() }

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(440)
          height: promptColumn.implicitHeight + Style.space(36)
          radius: root.cornerRadius
          color: root.background
          border.width: 1
          border.color: Util.alpha(root.pausedColor, 0.6)

          MouseArea { anchors.fill: parent; onClicked: clearInput.forceActiveFocus() }

          Column {
            id: promptColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(36)
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: root.t("clear.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.t("clear.body", { word: root.clearWord })
              color: root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              height: Style.space(32)
              radius: Style.space(4)
              color: root.chipBg
              border.width: 1
              border.color: root.clearWordTyped() ? root.pausedColor : root.lineColor

              TextInput {
                id: clearInput
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                selectByMouse: true

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelClearHistory()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.clearWordTyped()) root.confirmClearHistory()
                    event.accepted = true
                  }
                }
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                visible: clearInput.text.length === 0
                text: root.clearWord
                color: root.mutedFg
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Rectangle {
                width: cancelLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.space(4)
                color: cancelMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : root.chipBg

                Text {
                  id: cancelLabel
                  anchors.centerIn: parent
                  text: root.t("clear.cancel") + "  esc"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: cancelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.cancelClearHistory()
                }
              }

              Rectangle {
                readonly property bool armed: root.clearWordTyped()
                width: deleteLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.space(4)
                color: armed ? root.pausedColor : root.chipBg
                opacity: armed ? 1 : 0.5

                Text {
                  id: deleteLabel
                  anchors.centerIn: parent
                  text: root.t("clear.confirm") + "  enter"
                  color: parent.armed ? root.background : root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: parent.armed
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: parent.armed ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (parent.armed) root.confirmClearHistory()
                }
              }
            }
          }
        }
      }

      // ---------------------------------------------------------- layout

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(10)

        // ---- tabs (← / →). La activa se marca con color sólido + subrayado:
        // en las pruebas, un estado activo con opacidad leve no se distinguía.
        Item {
          id: tabBar
          width: parent.width
          height: Style.space(34)

          Row {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Style.space(4)

            Repeater {
              model: root.tabs

              delegate: Item {
                required property var modelData
                readonly property bool active: root.activeTab === modelData.key

                width: tabLabel.implicitWidth + Style.space(24)
                height: parent.height

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  anchors.verticalCenterOffset: -Style.space(2)
                  text: parent.modelData.icon + "  " + root.t(parent.modelData.label)
                  color: parent.active ? root.accent : root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: parent.active
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(2, Style.space(3))
                  radius: height / 2
                  color: root.accent
                  visible: parent.active
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.setTab(parent.modelData.key)
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }

          Text {
            anchors.right: pauseButton.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Style.space(2)
            text: "←  →  " + root.t("tab.switchHint")
            color: root.mutedFg
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Pausar/reanudar la captura a un clic (o Ctrl+=). En pausa se pinta en
          // rojo con "Resume" para que no se olvide encendida.
          Item {
            id: pauseButton
            anchors.right: gearButton.left
            anchors.rightMargin: Style.space(6)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: pauseRow.implicitWidth + Style.space(16)

            // En pausa, fondo rojo translúcido: solo el texto en rojo se pierde.
            Rectangle {
              anchors.centerIn: pauseRow
              width: pauseRow.implicitWidth + Style.space(14)
              height: pauseRow.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: Util.alpha(root.pausedColor, 0.22)
              visible: root.paused
            }

            Row {
              id: pauseRow
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(2)
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.paused ? "󰐊  " + root.t("pause.resume") : "󰏤  " + root.t("pause.pause")
                color: root.paused ? root.pausedColor : (pauseMouse.containsMouse ? root.accent : root.mutedFg)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.paused
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.space(3)
                color: root.chipBg
                width: pauseKey.implicitWidth + Style.space(10)
                height: Style.space(18)

                Text {
                  id: pauseKey
                  anchors.centerIn: parent
                  text: "ctrl+="
                  color: root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            MouseArea {
              id: pauseMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.pause(JSON.stringify({ paused: "toggle" }))
                keyCatcher.forceActiveFocus()
              }
            }
          }

          // Engranaje: abre/cierra Settings (Ctrl+,). Subrayado como una pestaña
          // cuando la vista está abierta.
          Item {
            id: gearButton
            readonly property bool active: root.activeTab === "settings"
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: gearLabel.implicitWidth + Style.space(20)

            Text {
              id: gearLabel
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(2)
              text: "󰒓  " + root.t("tab.settings")
              color: parent.active || gearMouse.containsMouse ? root.accent : root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: parent.active
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Math.max(2, Style.space(3))
              radius: height / 2
              color: root.accent
              visible: parent.active
            }

            MouseArea {
              id: gearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (parent.active) root.closeSettings()
                else root.openSettings()
                keyCatcher.forceActiveFocus()
              }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.normalBorderWidth
            color: root.lineColor
          }
        }

        // ---- buscador (60 %) + filtros (40 %) en una sola fila. Los filtros que
        // no caben se desvanecen a la derecha; con Ctrl+F y ← / → la tira se
        // desliza para mostrar siempre el activo.
        Item {
          id: searchBar
          width: parent.width
          height: root.headerHeight
          visible: root.activeTab === "clipboard"

          Item {
            id: searchArea
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.6)

            Text {
              id: searchIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍛"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Row {
              anchors.left: searchIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: countLabel.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                id: searchText
                width: Math.min(implicitWidth, parent.width - Style.space(6))
                text: root.filterText || root.t("search.placeholder") + "   (type:image  app:firefox  <2h  is:pinned)"
                color: root.foreground
                opacity: root.filterText.length > 0 ? 1 : 0.4
                font.family: root.fontFamily
                // El placeholder va más chico; lo que se escribe, grande.
                font.pixelSize: root.filterText.length > 0 ? Style.font.heading : Style.font.body
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Style.space(2))
                color: root.accent
                visible: root.cursorVisible && root.cursorActive && !root.chipMode
                height: root.filterText.length > 0 ? Style.font.heading : Style.font.body
              }
            }

            Text {
              id: countLabel
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.paused) return "⏸ " + root.t("count.paused")
                var shown = root.results.length
                var total = root.history.length
                if (shown === total) return total === 1 ? root.t("count.itemsOne") : root.t("count.items", { n: total })
                return root.t("count.of", { shown: shown, total: total })
              }
              color: root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            id: chipsRow
            anchors.left: searchArea.right
            anchors.leftMargin: Style.space(10)
            anchors.right: clearButton.left
            anchors.rightMargin: Style.space(8)
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // En modo filtros, la zona se enmarca para que se vea dónde está el teclado.
            Rectangle {
              anchors.fill: parent
              anchors.topMargin: Style.space(5)
              anchors.bottomMargin: Style.space(5)
              radius: Style.space(6)
              color: "transparent"
              border.width: 1
              border.color: Util.alpha(root.accent, 0.5)
              visible: root.chipMode
            }

            // Tecla que entra al modo filtros: siempre a la vista, resaltada en el modo.
            Rectangle {
              id: chipsKey
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.space(3)
              color: root.chipMode ? root.accent : root.chipBg
              width: chipsKeyText.implicitWidth + Style.space(10)
              height: Style.space(18)

              Text {
                id: chipsKeyText
                anchors.centerIn: parent
                text: "ctrl+f"
                color: root.chipMode ? root.background : root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.chipMode = !root.chipMode
                  keyCatcher.forceActiveFocus()
                }
              }
            }

            Flickable {
              id: chipsFlick
              anchors.left: chipsKey.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              clip: true
              contentWidth: chipsLine.width
              contentHeight: height
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds

              Behavior on contentX { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

              Row {
                id: chipsLine
                y: Math.round((chipsFlick.height - height) / 2)
                spacing: Style.space(6)

                Repeater {
                  id: chipsRepeater
                  model: root.typeChips

                  // Activo = relleno sólido con texto invertido: con solo una opacidad
                  // leve (como venía de alanfortlink) no se distinguía.
                  delegate: Rectangle {
                    required property var modelData
                    property string chipKey: modelData.key
                    property bool active: root.typeFilter === chipKey

                    radius: height / 2
                    color: active ? root.accent : (chipMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : root.chipBg)
                    width: chipLabel_.implicitWidth + Style.space(16)
                    height: Style.space(22)

                    Text {
                      id: chipLabel_
                      anchors.centerIn: parent
                      text: (modelData.icon ? modelData.icon + " " : "") + root.t(modelData.label)
                      color: parent.active ? root.background : root.mutedFg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: parent.active
                    }

                    MouseArea {
                      id: chipMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.setTypeFilter(parent.chipKey)
                        keyCatcher.forceActiveFocus()
                      }
                    }
                  }
                }
              }
            }

            // Sombras laterales: hay más filtros fuera de la vista.
            Rectangle {
              anchors.right: chipsFlick.right
              anchors.top: chipsFlick.top
              anchors.bottom: chipsFlick.bottom
              width: Style.space(44)
              visible: chipsFlick.contentX + chipsFlick.width < chipsFlick.contentWidth - 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: root.background }
              }
            }

            Rectangle {
              anchors.left: chipsFlick.left
              anchors.top: chipsFlick.top
              anchors.bottom: chipsFlick.bottom
              width: Style.space(28)
              visible: chipsFlick.contentX > 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.background }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }
          }

          // Vaciar historial (abre el diálogo que pide escribir la palabra).
          Rectangle {
            id: clearButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.space(4)
            color: clearMouse.containsMouse ? Util.alpha(root.pausedColor, 0.2) : root.chipBg
            width: Style.space(26)
            height: Style.space(22)

            Text {
              anchors.centerIn: parent
              text: "󰆴"
              color: clearMouse.containsMouse ? root.pausedColor : root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.requestClearHistory()
            }
          }
        }

        // ---- paused banner
        Rectangle {
          width: parent.width
          height: root.paused ? Style.space(24) : 0
          visible: root.paused && root.activeTab === "clipboard"
          radius: Style.cornerRadius
          color: Util.alpha(Color.urgent, 0.15)

          Text {
            anchors.centerIn: parent
            text: "⏸ " + root.t("banner.paused")
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- missing-dependency banner: command + run-in-terminal button
        Rectangle {
          width: parent.width
          height: root.missingDeps.length > 0 ? Style.space(24) : 0
          visible: root.missingDeps.length > 0 && root.activeTab === "clipboard"
          radius: Style.cornerRadius
          color: Util.alpha(Color.urgent, 0.15)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.missingDeps.length > 0
                    ? root.t("banner.missing", { name: root.t(root.missingDeps[0].name), cmd: root.missingDependencyCommand() })
                    : ""
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              radius: height / 2
              color: Util.alpha(Color.accent, 0.2)
              width: runLabel.implicitWidth + Style.space(14)
              height: Style.space(18)
              visible: root.missingDeps.length > 0

              Text {
                id: runLabel
                anchors.centerIn: parent
                text: "▶ " + root.t("banner.runTerminal")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.missingDeps.length === 0) return
                  root.close()
                  var cmd = root.missingDependencyCommand()
                  if (!cmd) return
                  cmd += '; echo; echo "' + root.t("terminal.done").replace(/'/g, "") + '"; read'
                  Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-c", cmd])
                }
              }
            }
          }
        }

        // ---- list + preview
        Item {
          width: parent.width
          visible: root.activeTab === "clipboard"
          height: parent.height - tabBar.height - root.headerHeight
                  - (root.paused ? Style.space(24) + Style.space(10) : 0)
                  - (root.missingDeps.length > 0 ? Style.space(24) + Style.space(10) : 0)
                  - footer.height - Style.space(30)

          ListView {
            id: resultList
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: root.listWidth
            model: displayModel
            clip: true
            spacing: Style.space(3)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property var row_    // results[i]: { row, score, positions }
              required property string derived
              required property int pinNo
              required property string titleHtml
              required property string subtitle

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property var entry: row_ ? row_.row.entry : null
              // Acciones a la vista solo con el mouse encima: con teclado no estorban.
              // El HoverHandler va en la fila entera (un hermano bajo el MouseArea no
              // recibe el hover), pero la zona del encabezado de grupo no cuenta.
              readonly property bool hovered: rowHover.hovered && rowHover.point.position.y >= headerH
              // Encabezado de grupo dibujado por la propia fila (la primera de cada
              // grupo). Las secciones de ListView duplicaban el título al rehacer
              // el modelo entero en cada búsqueda.
              readonly property string header: root.pinnedShown === 0 ? ""
                : index === 0 ? "pinned" : index === root.pinnedShown ? "history" : ""
              readonly property int headerH: header ? Style.space(26) : 0
              readonly property bool compact: index < root.pinnedShown
              readonly property int thumbSize: compact ? Style.space(22) : root.thumbSize

              width: resultList.width
              height: (compact ? root.pinnedRowHeight : root.rowHeight) + headerH
              color: "transparent"

              Item {
                width: parent.width
                height: row.headerH
                visible: row.header !== ""

                Text {
                  id: groupTitle
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(5)
                  text: row.header === "pinned" ? "★  " + root.t("group.pinned") : root.t("group.history")
                  color: row.header === "pinned" ? root.accent : root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }

                Text {
                  id: groupHint
                  anchors.left: groupTitle.right
                  anchors.leftMargin: Style.space(8)
                  anchors.baseline: groupTitle.baseline
                  text: row.header === "pinned" ? "ctrl+1…9 " + root.t("group.paste") : ""
                  color: root.mutedFg
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  anchors.left: groupHint.text ? groupHint.right : groupTitle.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: groupTitle.verticalCenter
                  height: Style.normalBorderWidth
                  color: root.lineColor
                }
              }

              // Fondo de la fila (bajo el encabezado, si lo hay).
              Rectangle {
                id: rowBg
                anchors.fill: parent
                anchors.topMargin: row.headerH
                radius: root.cornerRadius
                color: row.hasCursor ? root.selectedBackground : "transparent"
              }

              HoverHandler { id: rowHover }

              Row {
                anchors.fill: parent
                anchors.topMargin: row.headerH
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                // thumbnail for images, glyph tile otherwise
                Rectangle {
                  width: row.thumbSize
                  height: row.thumbSize
                  radius: row.compact ? Style.space(4) : Style.space(6)
                  color: root.chipBg
                  anchors.verticalCenter: parent.verticalCenter
                  clip: true

                  Image {
                    anchors.fill: parent
                    visible: row.derived === "image"
                    source: row.entry && row.entry.path ? Util.fileUrl(row.entry.path) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    sourceSize.width: 72
                    sourceSize.height: 72
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: row.derived !== "image"
                    text: Classify.typeIcon(row.derived)
                    color: root.foreground
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: row.compact ? Style.font.caption : Style.font.iconLarge
                  }
                }

                Column {
                  width: parent.width - row.thumbSize - Style.space(10) - pinMark.width
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: row.titleHtml
                    textFormat: Text.StyledText
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Text {
                    width: parent.width
                    visible: !row.compact
                    text: row.subtitle
                    color: root.rowMetaFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                // ★ + número del pin: Ctrl+N lo pega (solo hasta el 9).
                Row {
                  id: pinMark
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)
                  visible: row.pinNo > 0 && !row.hovered // con el mouse encima, sitio para las acciones

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.pinNo > 0 && row.pinNo <= 9
                    radius: Style.space(3)
                    color: Util.alpha(root.accent, 0.18)
                    width: pinNoText.implicitWidth + Style.space(10)
                    height: Style.space(18)

                    Text {
                      id: pinNoText
                      anchors.centerIn: parent
                      text: "ctrl+" + row.pinNo
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "★"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                anchors.topMargin: row.headerH
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                // A stray click must never paste into the window behind the
                // picker: single click selects, double click activates.
                onClicked: function(mouse) {
                  root.cancelEdit()
                  root.chipMode = false
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  if (mouse.clickCount === 2) root.pasteResult(root.currentResult)
                }
                onDoubleClicked: root.pasteResult(root.currentResult)
              }

              // Botones al pasar el mouse: fijar/soltar y borrar. Ocupan el sitio
              // del ★ y del número del pin, que se ocultan mientras tanto.
              Item {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: rowBg.verticalCenter
                visible: row.hovered
                width: rowActions.implicitWidth
                height: rowActions.implicitHeight

                Row {
                  id: rowActions
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Repeater {
                    model: [
                      { action: "pin", icon: row.entry && row.entry.pinned ? "󰐄" : "󰐃",
                        tip: root.t(row.entry && row.entry.pinned ? "row.unpin" : "row.pin") },
                      { action: "delete", icon: "󰆴", tip: root.t("row.delete") }
                    ]

                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool danger: modelData.action === "delete"
                      width: row.compact ? Style.space(24) : Style.space(28)
                      height: row.compact ? Style.space(24) : Style.space(28)
                      radius: Style.space(6)
                      color: actionMouse.containsMouse
                             ? Util.alpha(danger ? Color.urgent : root.accent, 0.2)
                             : root.chipBg

                      Text {
                        anchors.centerIn: parent
                        text: parent.modelData.icon
                        color: actionMouse.containsMouse ? (parent.danger ? Color.urgent : root.accent) : root.mutedFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }

                      MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (parent.modelData.action === "pin") root.togglePinIndex(row.index)
                          else root.requestRemoveIndex(row.index)
                          keyCatcher.forceActiveFocus()
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // divider between list and preview
          Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: root.listWidth + Style.space(6)
            width: Style.normalBorderWidth
            color: root.lineColor
          }

          // Nota del clip (Ctrl+M), encima del preview.
          Rectangle {
            id: noteBox
            readonly property string note: root.currentResult ? String(root.currentResult.row.entry.note || "") : ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.leftMargin: root.listWidth + Style.space(14)
            visible: note !== "" && !root.editing
            height: visible ? noteText.implicitHeight + Style.space(34) : 0
            radius: root.cornerRadius
            color: Util.alpha(root.accent, 0.1)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.35)

            Text {
              id: noteTitle
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: Style.space(8)
              text: "󰎚  " + root.t("preview.note") + "   ctrl+m"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              id: noteText
              anchors.top: noteTitle.bottom
              anchors.topMargin: Style.space(4)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: noteBox.note
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
              maximumLineCount: 4
              elide: Text.ElideRight
            }
          }

          PreviewPane {
            anchors.top: noteBox.visible ? noteBox.bottom : parent.top
            anchors.topMargin: noteBox.visible ? Style.space(8) : 0
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.leftMargin: root.listWidth + Style.space(14)
            result: root.currentResult
            openAction: function() { root.openResult(root.currentResult) }
            copyTextAction: function(text) { root.copyText(text) }
            pluginDir: root.pluginDir
            tr: root.t
            strings: root.strings
            visible: root.currentResult !== null && !root.editing
          }

          // Editor en el sitio del preview (F2 / Ctrl+E).
          Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.leftMargin: root.listWidth + Style.space(14)
            visible: root.editing
            radius: root.cornerRadius
            color: root.chipBg
            border.width: 1
            border.color: Util.alpha(root.accent, 0.6)

            Text {
              id: editorTitle
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: Style.space(12)
              text: root.editMode === "note" ? "󰎚  " + root.t("editor.noteTitle") : "󰏫  " + root.t("editor.title")
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.baseline: editorTitle.baseline
              text: "ctrl+enter " + root.t("editor.save") + "   ·   esc " + root.t("editor.cancel")
              color: root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flickable {
              id: editorFlick
              anchors.top: editorTitle.bottom
              anchors.topMargin: Style.space(10)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(12)
              clip: true
              contentWidth: width
              contentHeight: editor.contentHeight
              boundsBehavior: Flickable.StopAtBounds

              function ensureVisible(r) {
                if (contentY >= r.y) contentY = r.y
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
              }

              TextEdit {
                id: editor
                width: editorFlick.width
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                color: root.foreground
                selectionColor: Util.alpha(root.accent, 0.35)
                selectedTextColor: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onCursorRectangleChanged: editorFlick.ensureVisible(cursorRectangle)

                Keys.onPressed: function(event) {
                  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                  if (event.key === Qt.Key_Escape) {
                    root.cancelEdit()
                    event.accepted = true
                  } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                    root.saveEdit()
                    event.accepted = true
                  }
                }
              }
            }
          }

          // empty state
          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0
                    ? root.t("empty.clipboard")
                    : root.t("empty.noMatches", { q: root.filterText })
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        // ---- snippets: buscador (slug o nombre) + lista + "lo que se pega" / editor
        Item {
          id: snippetsPane
          width: parent.width
          height: parent.height - tabBar.height - footer.height - Style.space(20)
          visible: root.activeTab === "snippets"

          Item {
            id: snipBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.headerHeight

            Text {
              id: snipSearchIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍛"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Row {
              anchors.left: snipSearchIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: snipCount.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: Math.min(implicitWidth, parent.width - Style.space(6))
                text: root.snipQuery || root.t("snip.search") + "   (" + root.t("snip.searchHint") + ")"
                color: root.foreground
                opacity: root.snipQuery.length > 0 ? 1 : 0.4
                font.family: root.fontFamily
                font.pixelSize: root.snipQuery.length > 0 ? Style.font.heading : Style.font.body
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Style.space(2))
                color: root.accent
                visible: root.cursorVisible && !root.snipEditing
                height: root.snipQuery.length > 0 ? Style.font.heading : Style.font.body
              }
            }

            Text {
              id: snipCount
              anchors.right: snipNewButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.snippets.length === 1 ? root.t("snip.countOne") : root.t("snip.count", { n: root.snippets.length })
              color: root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              id: snipNewButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.space(4)
              color: snipNewMouse.containsMouse ? Util.alpha(root.accent, 0.2) : root.chipBg
              width: snipNewLabel.implicitWidth + Style.space(16)
              height: Style.space(24)

              Text {
                id: snipNewLabel
                anchors.centerIn: parent
                text: "󰐕 " + root.t("snip.new") + "   ctrl+n"
                color: snipNewMouse.containsMouse ? root.accent : root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: snipNewMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.newSnippet()
              }
            }
          }

          Item {
            anchors.top: snipBar.bottom
            anchors.topMargin: Style.space(10)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            ListView {
              id: snipList
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.listWidth
              model: root.snipResults
              clip: true
              spacing: Style.space(3)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: snipRow
                required property var modelData
                required property int index
                readonly property bool current: index === root.snipIndex
                width: snipList.width
                height: root.compactUi ? Style.space(40) : Style.space(46)
                radius: root.cornerRadius
                color: current ? root.selectedBackground : "transparent"

                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: snipRow.modelData.name || snipRow.modelData.slug || "—"
                    color: snipRow.current ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: !!snipRow.modelData.slug
                    text: snipRow.modelData.slug
                    color: root.rowMetaFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    if (root.snipEditing) root.cancelSnippetEdit()
                    root.snipIndex = snipRow.index
                    keyCatcher.forceActiveFocus()
                  }
                  onDoubleClicked: root.pasteSnippet(snipRow.modelData, false)
                }
              }
            }

            Column {
              anchors.centerIn: snipList
              width: snipList.width
              spacing: Style.space(8)
              visible: root.snipResults.length === 0

              Text {
                width: parent.width
                text: "󰅴"
                color: root.selectedText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                width: parent.width
                text: root.snippets.length === 0 ? root.t("snip.empty") : root.t("snip.noMatches", { q: root.snipQuery })
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }
            }

            Rectangle {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.leftMargin: root.listWidth + Style.space(6)
              width: Style.normalBorderWidth
              color: root.lineColor
            }

            // Preview: lo que se pega, ya con las variables resueltas.
            Item {
              id: snipPreview
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.left: parent.left
              anchors.leftMargin: root.listWidth + Style.space(14)
              visible: !root.snipEditing && root.currentSnippet !== null

              Text {
                id: snipPreviewName
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                text: root.currentSnippet ? (root.currentSnippet.name || "—") : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                id: snipPreviewSlug
                anchors.top: snipPreviewName.bottom
                anchors.topMargin: Style.space(2)
                anchors.left: parent.left
                text: root.currentSnippet ? root.currentSnippet.slug : ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: snipOutputLabel
                anchors.top: snipPreviewSlug.bottom
                anchors.topMargin: Style.space(12)
                anchors.left: parent.left
                text: root.t("snip.output").toUpperCase()
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              Rectangle {
                anchors.top: snipOutputLabel.bottom
                anchors.topMargin: Style.space(6)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: snipPreviewHints.top
                anchors.bottomMargin: Style.space(8)
                radius: root.cornerRadius
                color: root.chipBg

                Flickable {
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  clip: true
                  contentHeight: snipRendered.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds

                  Text {
                    id: snipRendered
                    width: parent.width
                    text: root.renderSnippet(root.currentSnippet)
                    textFormat: Text.MarkdownText
                    color: root.foreground
                    linkColor: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                  }
                }
              }

              Row {
                id: snipPreviewHints
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                spacing: Style.space(10)

                Repeater {
                  model: [
                    { keys: "enter", hint: "hint.paste" },
                    { keys: "ctrl+e", hint: "hint.edit" },
                    { keys: "ctrl+k", hint: "hint.variables" }
                  ]

                  delegate: Row {
                    required property var modelData
                    spacing: Style.space(4)

                    Rectangle {
                      radius: Style.space(3)
                      color: root.chipBg
                      width: snipHintKey.implicitWidth + Style.space(10)
                      height: Style.space(18)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: snipHintKey
                        anchors.centerIn: parent
                        text: modelData.keys
                        color: root.mutedFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.t(modelData.hint)
                      color: root.mutedFg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // Editor de snippet: nombre, slug y texto con botones de Markdown.
            Item {
              id: snipEditor
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.left: parent.left
              anchors.leftMargin: root.listWidth + Style.space(14)
              visible: root.snipEditing

              function commonKeys(event) {
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                if (event.key === Qt.Key_Escape) { root.cancelSnippetEdit(); event.accepted = true }
                else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) { root.saveSnippet(); event.accepted = true }
                else if (ctrl && event.key === Qt.Key_K) { root.openVars(); event.accepted = true }
              }

              Text {
                id: snipEditorTitle
                anchors.top: parent.top
                anchors.left: parent.left
                text: "󰏫  " + root.t(root.snipEditId ? "snip.editTitle" : "snip.newTitle")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Column {
                id: snipFields
                anchors.top: snipEditorTitle.bottom
                anchors.topMargin: Style.space(10)
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(4)

                Text {
                  text: root.t("snip.field.name")
                  color: root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(30)
                  radius: Style.space(4)
                  color: root.chipBg
                  border.width: 1
                  border.color: snipNameInput.activeFocus ? Util.alpha(root.accent, 0.6) : root.lineColor

                  TextInput {
                    id: snipNameInput
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    selectByMouse: true
                    KeyNavigation.tab: snipSlugInput
                    Keys.onPressed: function(event) { snipEditor.commonKeys(event) }
                  }
                }

                Item { width: 1; height: Style.space(4) }

                Text {
                  text: root.t("snip.field.slug")
                  color: root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(30)
                  radius: Style.space(4)
                  color: root.chipBg
                  border.width: 1
                  border.color: snipSlugTaken.visible ? root.pausedColor
                              : snipSlugInput.activeFocus ? Util.alpha(root.accent, 0.6) : root.lineColor

                  TextInput {
                    id: snipSlugInput
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    selectByMouse: true
                    KeyNavigation.tab: snipBodyEdit
                    KeyNavigation.backtab: snipNameInput
                    Keys.onPressed: function(event) { snipEditor.commonKeys(event) }
                  }
                }

                Text {
                  id: snipSlugTaken
                  visible: root.snipEditing && Snippets.slugTaken(root.snippets, snipSlugInput.text, root.snipEditId)
                  text: "⚠ " + root.t("snip.slugTaken")
                  color: root.pausedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Item { width: 1; height: Style.space(4) }

                Text {
                  text: root.t("snip.field.body")
                  color: root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // Barra de Markdown: 5 formatos + variables.
                Row {
                  spacing: Style.space(4)

                  Repeater {
                    model: [
                      // Letras con su propio estilo: los glifos de Nerd Font de
                      // "negrita/cursiva" se confundían con los de alinear.
                      { id: "bold", icon: "B", tip: "snip.tb.bold" },
                      { id: "italic", icon: "I", tip: "snip.tb.italic" },
                      { id: "code", icon: "</>", tip: "snip.tb.code" },
                      { id: "codeBlock", icon: "```", tip: "snip.tb.codeBlock" },
                      { id: "list", icon: "•", tip: "snip.tb.list" },
                      { id: "vars", icon: "{ }", tip: "snip.tb.variables" }
                    ]

                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool wide: modelData.id === "vars"
                      width: wide ? tbLabel.implicitWidth + Style.space(16) : Math.max(Style.space(30), tbLabel.implicitWidth + Style.space(14))
                      height: Style.space(26)
                      radius: Style.space(4)
                      color: tbMouse.containsMouse ? Util.alpha(root.accent, 0.2) : root.chipBg

                      Text {
                        id: tbLabel
                        anchors.centerIn: parent
                        text: parent.wide ? parent.modelData.icon + " " + root.t(parent.modelData.tip) : parent.modelData.icon
                        color: tbMouse.containsMouse ? root.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: parent.wide ? Style.font.caption : Style.font.body
                        font.bold: parent.modelData.id === "bold"
                        font.italic: parent.modelData.id === "italic"
                      }

                      MouseArea {
                        id: tbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          var id = parent.modelData.id
                          if (id === "bold") root.wrapSelection("**", "**")
                          else if (id === "italic") root.wrapSelection("_", "_")
                          else if (id === "code") root.wrapSelection("`", "`")
                          else if (id === "codeBlock") root.wrapSelection("```\n", "\n```")
                          else if (id === "list") root.listifySelection()
                          else root.openVars()
                        }
                      }
                    }
                  }
                }
              }

              Rectangle {
                anchors.top: snipFields.bottom
                anchors.topMargin: Style.space(6)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: snipEditorHint.top
                anchors.bottomMargin: Style.space(8)
                radius: Style.space(4)
                color: root.chipBg
                border.width: 1
                border.color: snipBodyEdit.activeFocus ? Util.alpha(root.accent, 0.6) : root.lineColor

                Flickable {
                  id: snipBodyFlick
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  clip: true
                  contentWidth: width
                  contentHeight: snipBodyEdit.contentHeight
                  boundsBehavior: Flickable.StopAtBounds

                  function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                  }

                  TextEdit {
                    id: snipBodyEdit
                    width: snipBodyFlick.width
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    color: root.foreground
                    selectionColor: Util.alpha(root.accent, 0.35)
                    selectedTextColor: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    onCursorRectangleChanged: snipBodyFlick.ensureVisible(cursorRectangle)
                    KeyNavigation.backtab: snipSlugInput

                    Keys.onPressed: function(event) {
                      var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                      if (ctrl && event.key === Qt.Key_B) { root.wrapSelection("**", "**"); event.accepted = true }
                      else if (ctrl && event.key === Qt.Key_I) { root.wrapSelection("_", "_"); event.accepted = true }
                      else snipEditor.commonKeys(event)
                    }
                  }
                }
              }

              Text {
                id: snipEditorHint
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                text: "ctrl+enter " + root.t("editor.save") + "   ·   esc " + root.t("editor.cancel") + "   ·   ctrl+k " + root.t("hint.variables")
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- settings: componentes nativos de Omarchy (Toggle, ButtonGroup)
        Item {
          width: parent.width
          height: parent.height - tabBar.height - footer.height - Style.space(20)
          visible: root.activeTab === "settings"

          ListView {
            id: settingsList
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            model: root.settingsRows
            clip: true
            spacing: Style.space(6)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: settingRow
              required property var modelData
              required property int index
              readonly property bool hasCursor: index === root.settingsCursor
              width: settingsList.width
              height: modelData.section ? sectionHeader.implicitHeight + Style.space(14)
                    : modelData.type === "bool" ? toggleRow.implicitHeight : choiceRow.implicitHeight

              PanelSectionHeader {
                id: sectionHeader
                visible: !!settingRow.modelData.section
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                text: root.t(String(settingRow.modelData.section || "")).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Toggle {
                id: toggleRow
                visible: settingRow.modelData.type === "bool"
                width: parent.width
                label: settingRow.modelData.label ? root.t(settingRow.modelData.label) : ""
                description: settingRow.modelData.desc ? root.t(settingRow.modelData.desc) : ""
                checked: visible ? !!root.settingValue(settingRow.modelData.key) : false
                hasCursor: settingRow.hasCursor
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  root.settingsCursor = settingRow.index
                  root.changeSetting(settingRow.modelData, 1)
                  keyCatcher.forceActiveFocus()
                }
              }

              // Fila de "elige uno": misma piel que Toggle (BorderSurface +
              // controlFill) para que la página se lea como una sola lista.
              BorderSurface {
                id: choiceRow
                visible: settingRow.modelData.type === "choice" || settingRow.modelData.type === "button"
                width: parent.width
                implicitHeight: Math.max(54, choiceText.implicitHeight + Style.spacing.huge)
                radius: Style.cornerRadius
                readonly property bool hot: settingRow.hasCursor || choiceHover.hovered
                color: Style.controlFill(false, hot, root.foreground, root.accent)
                borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", root.foreground, root.accent)

                HoverHandler { id: choiceHover }

                Column {
                  id: choiceText
                  anchors.left: parent.left
                  anchors.right: choiceGroup.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs

                  Text {
                    width: parent.width
                    text: settingRow.modelData.label ? root.t(settingRow.modelData.label) : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: settingRow.modelData.desc ? root.t(settingRow.modelData.desc) : ""
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }

                ButtonGroup {
                  id: choiceGroup
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  focusable: false
                  // Fila "button": un solo botón (Exportar…/Importar…) sin selección.
                  options: settingRow.modelData.type === "button"
                    ? [{ value: "run", label: root.t(settingRow.modelData.button) }]
                    : (settingRow.modelData.options || []).map(function(o) {
                        return { value: o.value, label: root.t(o.label) }
                      })
                  value: choiceRow.visible && settingRow.modelData.type === "choice" ? String(root.settingValue(settingRow.modelData.key)) : ""
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onChanged: function(v) {
                    root.settingsCursor = settingRow.index
                    if (settingRow.modelData.type === "button") root.runBackup(settingRow.modelData.key)
                    else root.setChoice(settingRow.modelData, v)
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }
        }

        // ---- footer key hints
        Row {
          id: footer
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.activeTab === "settings" ? [
              { keys: "↑/↓", hint: "hint.move" },
              { keys: "space", hint: "hint.toggle" },
              { keys: "←/→", hint: "hint.change" },
              { keys: "esc", hint: "hint.back" }
            ] : root.editing ? [
              { keys: "ctrl+enter", hint: "hint.save" },
              { keys: "esc", hint: "hint.cancel" }
            ] : root.activeTab === "snippets" && root.snipEditing ? [
              { keys: "ctrl+enter", hint: "hint.save" },
              { keys: "esc", hint: "hint.cancel" },
              { keys: "ctrl+k", hint: "hint.variables" },
              { keys: "tab", hint: "hint.nextField" }
            ] : root.activeTab === "snippets" ? [
              { keys: "↑/↓", hint: "hint.navigate" },
              { keys: "enter", hint: "hint.paste" },
              { keys: "shift+enter", hint: "hint.copy", full: true },
              { keys: "ctrl+n", hint: "hint.new" },
              { keys: "f2", hint: "hint.edit" },
              { keys: "ctrl+k", hint: "hint.variables" },
              { keys: "del", hint: "hint.remove" },
              { keys: "←/→", hint: "hint.switchTab", full: true },
              { keys: "esc", hint: "hint.close" }
            ].filter(function(h) { return !h.full || !root.compactUi }) : [
              { keys: "ctrl+n/p", hint: "hint.navigate" },
              { keys: "enter", hint: "hint.paste" },
              { keys: "shift+enter", hint: "hint.copy" },
              { keys: "ctrl+o", hint: "hint.open", full: true },
              { keys: "tab", hint: "hint.pin" },
              { keys: "f2", hint: "hint.edit", full: true },
              { keys: "ctrl+.", hint: "hint.actions" },
              { keys: "del", hint: "hint.remove" },
              { keys: "esc", hint: "hint.close" }
            ].filter(function(h) { return !h.full || !root.compactUi })

            delegate: Row {
              required property var modelData
              spacing: Style.space(4)

              Rectangle {
                radius: Style.space(3)
                color: root.chipBg
                width: keyText.implicitWidth + Style.space(10)
                height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: keyText
                  anchors.centerIn: parent
                  text: modelData.keys
                  color: root.mutedFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                text: root.t(modelData.hint)
                color: root.mutedFg
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ display model

  // results → displayModel rows. Wrapped in function so it can be called from
  // rebuild(); title/subtitle strings precomputed here, not in delegates.
  function syncDisplayModel() {
    displayModel.clear()
    for (var i = 0; i < root.results.length; i++) {
      var r = root.results[i]
      var e = r.row.entry
      var derived = r.row.type
      var titleHtml = ""
      if (e.type === "image") {
        titleHtml = e.qr
          ? Fuzzy.escapeHtml(Classify.firstLine(e.qr, 60))
          : root.t("row.image") + (e.mime ? " · " + e.mime.replace("image/", "").toUpperCase() : "")
                + (e.w && e.h ? " · " + e.w + "×" + e.h : "")
      } else if (e.type === "files") {
        var base = Classify.fileBase(e.paths[0])
        titleHtml = Fuzzy.escapeHtml(e.paths.length > 1 ? base + "  " + root.t("row.more", { n: e.paths.length - 1 }) : base)
      } else {
        titleHtml = Fuzzy.highlightFirstLine(e.text, r.positions, "<b><font color=\"" + root.accentHex() + "\">", "</font></b>")
      }
      if (e.note) titleHtml += "  <font color=\"" + root.accentHex() + "\">󰎚</font>"

      // Debajo de cada clip, solo cuándo y cuánto: el resto del detalle está en el preview.
      var subtitleParts = []
      if (r.row.ts) subtitleParts.push(Classify.formatAge(r.row.ts, Math.floor(Date.now() / 1000), root.strings))
      if (r.row.bytes > 0) subtitleParts.push(Classify.formatBytes(r.row.bytes))

      displayModel.append({
        row_: r,
        pinNo: e.pinned ? root.pinNumber(e.id) : 0,
        derived: derived,
        titleHtml: titleHtml,
        subtitle: subtitleParts.join("  ·  ")
      })
    }
  }

  // 6-digit hex for rich-text <font color> tags, whatever toString() returns.
  function accentHex() {
    var s = root.accent.toString()
    return "#" + s.slice(-6)
  }

  onResultsChanged: syncDisplayModel()
}
