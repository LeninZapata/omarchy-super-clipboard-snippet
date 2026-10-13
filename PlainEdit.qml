import QtQuick
import "Editing.js" as Editing

// Campo de texto plano dibujado por el plugin (una línea o varias). NO es un
// TextInput/TextEdit: un campo nativo editable vuelve a leer el texto del
// portapapeles ajeno en cada cambio (canPaste), sin tope de tamaño ni de tiempo,
// y el shell es compartido (reparo del marketplace, issue #11191). Este nunca
// toca el portapapeles: Ctrl+V pega lo que da `pasteText` (el último clip de
// texto del historial, que capture.py ya leyó con su tope) y Ctrl+C/X entregan
// el texto a `copyText`. La lógica de edición vive en Editing.js.
//
// Se usa como un TextInput: text, cursorPosition, selectionStart/End, length,
// insert(), remove(), select(), getText(), forceActiveFocus(). Las teclas pasan
// primero por la señal preKey(event): si el que lo usa la acepta, el campo no
// la procesa.
Item {
  id: field

  property string text: ""
  property bool multiline: false
  property string fontFamily: ""
  property int fontPixelSize: 14
  property color color: "white"
  property color selectionColor: Qt.rgba(0.4, 0.6, 1, 0.35)
  property string placeholder: ""
  property color placeholderColor: "gray"
  property Item nextField: null
  property Item prevField: null
  property var pasteText: function() { return "" }
  property var copyText: function(text) {}

  property int cursorPosition: 0
  property int anchorPosition: 0
  readonly property int selectionStart: Math.min(cursorPosition, anchorPosition)
  readonly property int selectionEnd: Math.max(cursorPosition, anchorPosition)
  readonly property int length: text.length
  readonly property string selectedText: text.slice(selectionStart, selectionEnd)

  signal preKey(var event)

  clip: true
  implicitHeight: lineHeight

  readonly property real lineHeight: Math.ceil(metrics.height)
  // averageCharacterWidth es una propiedad: avisa cuando cambia la fuente. Una
  // llamada a advanceWidth() en un binding se quedaría con la fuente inicial.
  readonly property real charWidth: Math.max(1, metrics.averageCharacterWidth)
  readonly property int cols: Math.max(1, Math.floor((width - 2) / charWidth))
  readonly property var rows: multiline ? Editing.wrap(text, cols) : [[0, text.length]]
  readonly property real offsetY: multiline ? 0 : Math.max(0, (height - lineHeight) / 2)
  property real scrollX: 0

  // Mover el cursor desde fuera (cursorPosition = n) quita la selección, como
  // en un campo normal; los movimientos internos fijan el ancla a mano.
  property bool settingCursor: false
  onCursorPositionChanged: {
    if (!settingCursor) anchorPosition = cursorPosition
    blinkOn = true
    Qt.callLater(ensureCursorVisible)
  }

  onTextChanged: {
    if (cursorPosition > text.length || anchorPosition > text.length) setCursor(Math.min(cursorPosition, text.length), Math.min(anchorPosition, text.length))
  }

  FontMetrics {
    id: metrics
    font.family: field.fontFamily
    font.pixelSize: field.fontPixelSize
  }

  // ------------------------------------------------------------ API tipo TextInput
  function setCursor(cursor, anchor) {
    settingCursor = true
    cursorPosition = Editing.clamp(cursor, 0, text.length)
    anchorPosition = Editing.clamp(anchor, 0, text.length)
    settingCursor = false
  }

  function select(a, b) { setCursor(b, a) }
  function selectAll() { setCursor(text.length, 0) }
  function getText(a, b) { return text.slice(Math.min(a, b), Math.max(a, b)) }

  function insert(at, s) {
    var str = String(s)
    var p = Editing.clamp(at, 0, text.length)
    var c = cursorPosition >= p ? cursorPosition + str.length : cursorPosition
    var a = anchorPosition >= p ? anchorPosition + str.length : anchorPosition
    commit({ text: text.slice(0, p) + str + text.slice(p), cursor: c, anchor: a }, "")
  }

  function remove(a, b) {
    var s = Math.min(a, b), e = Math.max(a, b)
    var shift = function(pos) { return pos <= s ? pos : Math.max(s, pos - (e - s)) }
    commit({ text: text.slice(0, s) + text.slice(e), cursor: shift(cursorPosition), anchor: shift(anchorPosition) }, "")
  }

  // ------------------------------------------------------------ deshacer
  property var undoStack: []
  property var redoStack: []
  property string lastEditKind: ""

  function state() { return { text: text, cursor: cursorPosition, anchor: anchorPosition } }

  // Aplica un estado nuevo. Las letras seguidas se agrupan en un solo paso de deshacer.
  function commit(st, kind) {
    if (st.text === text && st.cursor === cursorPosition && st.anchor === anchorPosition) return
    if (st.text !== text && !(kind === "type" && lastEditKind === "type")) {
      undoStack.push(state())
      if (undoStack.length > 200) undoStack.shift()
      redoStack = []
    }
    lastEditKind = kind
    text = st.text
    setCursor(st.cursor, st.anchor)
  }

  function undo() {
    if (!undoStack.length) return
    redoStack.push(state())
    var st = undoStack.pop()
    lastEditKind = ""
    text = st.text
    setCursor(st.cursor, st.anchor)
  }

  function redo() {
    if (!redoStack.length) return
    undoStack.push(state())
    var st = redoStack.pop()
    lastEditKind = ""
    text = st.text
    setCursor(st.cursor, st.anchor)
  }

  // ------------------------------------------------------------ geometría
  function shown(s) { return s.replace(/\t/g, " ") }

  function rowX(row, pos) {
    void metrics.font // los bindings que llaman aquí se recalculan si cambia la fuente
    var r = rows[row]
    if (!r) return 0
    return metrics.advanceWidth(shown(text.slice(r[0], Editing.clamp(pos, r[0], r[1]))))
  }

  // Posición del texto más cercana a x dentro de una fila (búsqueda binaria).
  function posInRow(row, x) {
    var r = rows[Editing.clamp(row, 0, rows.length - 1)]
    var lo = r[0], hi = r[1]
    while (lo < hi) {
      var mid = (lo + hi) >> 1
      var left = rowX(row, mid), right = rowX(row, Editing.nextPos(text, mid))
      if (x < (left + right) / 2) hi = mid
      else lo = Editing.nextPos(text, mid)
    }
    return Math.min(lo, r[1])
  }

  function posAt(x, y) {
    var row = Editing.clamp(Math.floor((y - offsetY) / lineHeight), 0, rows.length - 1)
    return posInRow(row, x + scrollX)
  }

  function cursorRow() { return Editing.rowOf(rows, cursorPosition) }

  function ensureCursorVisible() {
    var row = cursorRow()
    if (multiline) {
      var top = row * lineHeight
      if (top < flick.contentY) flick.contentY = top
      else if (top + lineHeight > flick.contentY + flick.height) flick.contentY = top + lineHeight - flick.height
    } else {
      var cx = rowX(0, cursorPosition)
      if (cx - scrollX > width - 2) scrollX = cx - width + 2
      else if (cx < scrollX) scrollX = cx
      if (scrollX > 0 && rowX(0, text.length) - scrollX < width - 2) scrollX = Math.max(0, rowX(0, text.length) - width + 2)
    }
  }

  // ------------------------------------------------------------ teclado
  property real goalX: -1 // ↑↓ conservan la columna aunque pasen por filas cortas

  function moveTo(pos, extend) {
    setCursor(pos, extend ? anchorPosition : pos)
  }

  function moveRows(delta, extend) {
    var row = cursorRow()
    var target = row + delta
    if (goalX < 0) goalX = rowX(row, cursorPosition)
    var x = goalX
    if (target < 0) moveTo(0, extend)
    else if (target >= rows.length) moveTo(text.length, extend)
    else moveTo(posInRow(target, x), extend)
    goalX = x
  }

  function handleKey(event) {
    var k = event.key
    var m = event.modifiers
    var ctrl = (m & Qt.ControlModifier) !== 0
    var shift = (m & Qt.ShiftModifier) !== 0
    var st = state()
    var sel = Editing.hasSelection(st)
    if (k !== Qt.Key_Up && k !== Qt.Key_Down && k !== Qt.Key_PageUp && k !== Qt.Key_PageDown) goalX = -1

    if (k === Qt.Key_Left) {
      moveTo(ctrl ? Editing.wordLeft(text, cursorPosition) : (sel && !shift ? selectionStart : Editing.prevPos(text, cursorPosition)), shift)
    } else if (k === Qt.Key_Right) {
      moveTo(ctrl ? Editing.wordRight(text, cursorPosition) : (sel && !shift ? selectionEnd : Editing.nextPos(text, cursorPosition)), shift)
    } else if (k === Qt.Key_Home) {
      moveTo(ctrl ? 0 : Editing.lineStart(text, cursorPosition), shift)
    } else if (k === Qt.Key_End) {
      moveTo(ctrl ? text.length : Editing.lineEnd(text, cursorPosition), shift)
    } else if ((k === Qt.Key_Up || k === Qt.Key_Down) && multiline) {
      moveRows(k === Qt.Key_Up ? -1 : 1, shift)
    } else if ((k === Qt.Key_PageUp || k === Qt.Key_PageDown) && multiline) {
      var page = Math.max(1, Math.floor(flick.height / lineHeight) - 1)
      moveRows(k === Qt.Key_PageUp ? -page : page, shift)
    } else if (k === Qt.Key_Backspace) {
      commit(Editing.backspace(st, ctrl), "delete")
    } else if (k === Qt.Key_Delete) {
      commit(Editing.deleteForward(st, ctrl), "delete")
    } else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && multiline && !ctrl) {
      commit(Editing.replaceSelection(st, "\n"), "")
    } else if (k === Qt.Key_Tab && !ctrl) {
      if (nextField) nextField.forceActiveFocus()
      else if (multiline) commit(Editing.replaceSelection(st, "\t"), "")
      else return false
    } else if (k === Qt.Key_Backtab) {
      if (prevField) prevField.forceActiveFocus()
      else return false
    } else if (ctrl && k === Qt.Key_A) {
      selectAll()
    } else if (ctrl && (k === Qt.Key_C || k === Qt.Key_X)) {
      if (!sel) return true
      copyText(Editing.selectedText(st))
      if (k === Qt.Key_X) commit(Editing.replaceSelection(st, ""), "")
    } else if (ctrl && k === Qt.Key_V) {
      var pasted = String(pasteText() || "")
      if (!multiline) pasted = pasted.replace(/\r?\n/g, " ")
      if (pasted) commit(Editing.replaceSelection(st, pasted), "")
    } else if (ctrl && k === Qt.Key_Z) {
      if (shift) redo()
      else undo()
    } else if (ctrl && k === Qt.Key_Y) {
      redo()
    } else if (ctrl && k === Qt.Key_U) {
      commit(Editing.deleteToLineStart(st), "delete")
    } else if (!ctrl && event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      commit(Editing.replaceSelection(st, event.text), event.text === " " ? "" : "type")
    } else {
      return false
    }
    return true
  }

  Keys.onPressed: function(event) {
    event.accepted = false
    field.preKey(event)
    if (event.accepted) return
    event.accepted = field.handleKey(event)
  }

  // ------------------------------------------------------------ dibujo
  property bool blinkOn: true
  Timer {
    running: field.activeFocus
    interval: 530
    repeat: true
    onTriggered: field.blinkOn = !field.blinkOn
  }

  Text {
    x: 0
    y: field.offsetY
    visible: field.text.length === 0 && field.placeholder.length > 0
    text: field.placeholder
    textFormat: Text.PlainText
    color: field.placeholderColor
    font: metrics.font
  }

  Flickable {
    id: flick
    anchors.fill: parent
    interactive: field.multiline
    clip: true
    contentWidth: width
    contentHeight: Math.max(height, field.rows.length * field.lineHeight)
    boundsBehavior: Flickable.StopAtBounds

    readonly property int firstRow: Math.max(0, Math.floor(contentY / field.lineHeight))
    readonly property int visibleRows: Math.ceil(height / field.lineHeight) + 1

    // Solo se dibujan las filas visibles: un clip enorme no crea miles de Text.
    Repeater {
      model: Math.max(0, Math.min(flick.visibleRows, field.rows.length - flick.firstRow))

      delegate: Item {
        required property int index
        readonly property int row: flick.firstRow + index
        readonly property var span: field.rows[row] || [0, 0]
        x: -field.scrollX
        y: field.offsetY + row * field.lineHeight
        width: flick.width + field.scrollX
        height: field.lineHeight

        Rectangle {
          readonly property int a: Math.max(field.selectionStart, parent.span[0])
          readonly property int b: Math.min(field.selectionEnd, parent.span[1])
          // una fila vacía dentro de la selección se marca con un hueco chico
          readonly property bool covers: field.selectionEnd > field.selectionStart
                                         && field.selectionStart <= parent.span[1] && field.selectionEnd > parent.span[0]
          visible: covers
          x: field.rowX(parent.row, a)
          width: Math.max(b > a ? field.rowX(parent.row, b) - x : 0, field.charWidth / 2)
          height: parent.height
          color: field.selectionColor
        }

        Text {
          y: 0
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: field.shown(field.text.slice(parent.span[0], parent.span[1]))
          textFormat: Text.PlainText
          color: field.color
          font: metrics.font
        }
      }
    }

    Rectangle {
      readonly property int row: field.cursorRow()
      x: field.rowX(row, field.cursorPosition) - field.scrollX
      y: field.offsetY + row * field.lineHeight
      width: 2
      height: field.lineHeight
      color: field.color
      visible: field.activeFocus && field.blinkOn
    }

    MouseArea {
      width: flick.width
      height: flick.contentHeight
      cursorShape: Qt.IBeamCursor
      preventStealing: true
      onPressed: function(mouse) {
        field.forceActiveFocus()
        field.goalX = -1
        var pos = field.posAt(mouse.x, mouse.y)
        field.moveTo(pos, (mouse.modifiers & Qt.ShiftModifier) !== 0)
      }
      onPositionChanged: function(mouse) {
        if (pressed) field.moveTo(field.posAt(mouse.x, mouse.y), true)
      }
      onDoubleClicked: function(mouse) {
        var w = Editing.wordAt(field.text, field.posAt(mouse.x, mouse.y))
        field.select(w[0], w[1])
      }
    }
  }
}
