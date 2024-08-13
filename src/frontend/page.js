// Utils ---------------------------------------------

function flr(n) {
  return Math.floor(n)
}

function p2(smth) {
  return String(smth).padStart(2, '0')
}

function unixToFormattedDate(unixTimestamp) {
  let oo = new Date(unixTimestamp * 1000) // Convert to milliseconds
  let yyyy = oo.getFullYear()
  let mm = p2(oo.getMonth() + 1)
  let dd = p2(oo.getDate())
  let hh = p2(oo.getHours())
  let tt = p2(oo.getMinutes())
  return `${yyyy}-${mm}-${dd} ${hh}:${tt}`
}

function unixNow() {
  return flr(Date.now() / 1000)
}

function toUnixTimestamp(dateObject) {
  return flr(dateObject.getTime() / 1000)
}


function mapObjAcc(obj, fn) {
  var result = []
  for (let key in obj) {
    let val = obj[key]
    result.push(fn(key, val))
  }
  return result
}

function last(arr) {
  return arr[arr.length - 1]
}

// DOM Utils -------------------------------------------

function q(sel) {
  return document.querySelector(sel)
}

function qa(sel) {
  return document.querySelectorAll(sel)
}

function setAttrs(el, attrsObj) {
  for (let key in attrsObj) {
    let value = attrsObj[key]
    el.setAttribute(key, value)
  }
}

function newElement(tag, attrs = {}, inner = '') {
  let el = document.createElement(tag)
  setAttrs(el, attrs)
  el.innerText = inner
  return el
}

function insertAtCurrPos(el, text) {
  let pos = el.selectionStart
  let prev = el.value.substring(0, pos)
  let next = el.value.substring(pos, el.value.length)

  el.value = prev + text + ' \n' + next
}

// DataBase -------------------------------------------

// ----- low level

function clearDB() {
  localStorage.clear()
}

function missingItemDB(key) {
  return localStorage.getItem(key) === null
}
function existsItemDB(key) {
  return !missingItemDB(key)
}

function getItemDB(key) {
  return JSON.parse(localStorage.getItem(key))
}
function setItemDB(key, val) {
  return localStorage.setItem(key, JSON.stringify(val))
}

function getAllItemsDB() {
  let result = {}
  for (let i = 0; i < localStorage.length; i++) {
    let key = localStorage.key(i)
    let value = localStorage.getItem(key)
    result[key] = value
  }
  return key
}

// ----- domain level

function getNoteReviewHistory(noteId) {
  return getItemDB(noteId) ?? []
}

function addNoteReviewHistory(noteId, utime, score, minSecOffset) {
  let snap = [utime, score]
  let history = getNoteReviewHistory(noteId)

  if ((0 < history.length) && (utime - last(history)[0] < minSecOffset))
    history.pop()

  history.push(snap)
  console.log(history)
  setItemDB(noteId, history)

  return history
}

// Actions --------------------------------------------

// Globals ---------------------------------------------

// score  : "-1 0 +1"
// history: [{time, score}] always sorted by time

var allNotes = {}
var currentNoteId = null

const scoreFunctions = {
  'passed': (now, created, history) => now - created,
  'history_len': (now, created, history) => history.length,
}

var current_score_function = 'passed'


// Unpoly Setup ----------------------------------------


up.macro('[smooth-link]', link => {
  setAttrs(link, {
    'up-transition': 'cross-fade',
    'up-duration': '250',
    'up-follow': '',
  })
})

up.macro('[note-data]', script => {
  // let i = script.getAttribute("index")
  let note = JSON.parse(script.innerHTML)
  allNotes[note.id] = note
})

up.macro('[parse-unix-date]', el => {
  let unixt = parseInt(el.innerText.trim())
  el.innerHTML = unixToFormattedDate(unixt)
})

up.compiler('#suggested-tags .btn', el => {
  let name = el.innerText.replace(' ', '')
  el.onclick = () => {
    insertAtCurrPos(q`#tag-query-input`, name)
  }
})

up.compiler('#tag-query-btn', el => {
  el.onclick = () => {
    let exprs =
      q`#tag-query-input`
        .value
        .split('\n')
        .map(s => s.trim())
        .filter(s => s.length != 0)
        .map(s => s.split(/\s+/g))

    // TODO
    console.log(exprs)
  }
})

up.compiler('#import-db-btn', el => {
  el.onclick = () => {
    // TODO
  }
})

up.compiler('#export-db-btn', el => {
  el.onclick = () => {
    // TODO
  }
})

up.compiler('#clear-db-btn', el => {
  el.onclick = () => {
    let answer = confirm("Are you sure?")
    if (answer) {
      clearDB()
    }
  }
})

up.compiler('#score-functions-input', select => {
  function valueChanged() {
    let now = unixNow()
    current_score_function = select.value
    let fn = scoreFunctions[select.value]
    let coeff = (q`#inverse-result-checkbox`.checked ? -1 : +1)
    let acc = mapObjAcc(allNotes,
      (id, note) => [id, coeff * fn(now, note.timestamp, getNoteReviewHistory(id))]) // [id, score]

    acc.sort((a, b) => b[1] - a[1]) // sort by score

    let sortedNotes = acc.map(([id, score]) => {
      let el = q(`[note-id=${id}]`)
      el.querySelector('[note-score]').innerText = score
      return el
    })

    q`#notes-rows`.replaceChildren(...sortedNotes)
  }

  select.replaceChildren(
    ...Object
      .keys(scoreFunctions)
      .map(t => newElement("option", { value: t }, t))
  )
  select.value = current_score_function
  select.onchange = valueChanged
  valueChanged()
})

up.compiler('#inverse-result-checkbox', input => {
  input.onchange = () => {
    let t = input.checked
    let select = q`#score-functions-input`
    select.onchange()
  }
})

up.compiler('.note-view', el => {
  currentNoteId = el.getAttribute('note-id')
})

up.compiler('[name=note-review-btn]', input => {
  input.onchange = () => {
    addNoteReviewHistory(currentNoteId, unixNow(), parseInt(input.value), 10)
  }
})

up.compiler('[path-breadcrumb]', el => {
  let subs = el.innerHTML
    .trim()
    .split(/[\/\\]/g)
    .map(p => newElement('li', { 'class': 'breadcrumb-item py-2' }, p))

  last(subs).classList.add('text-primary')

  el.replaceChildren(...subs)
})