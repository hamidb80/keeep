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

// Actions --------------------------------------------

function sortNotes() {
  // TODO
}

// Globals ---------------------------------------------

// score  : "-1 0 +1"
// history: [{time, score}] always sorted by time

var allNotes = {}

const score_functions = {
  'passed': (now, created, history) => now - created,
  'created': (now, created, history) => created,
}

const default_score_function = 'passed'


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

up.compiler('#score-functions-input', select => {
  function valueChanged() {
    let now = unixNow()
    let fn = score_functions[select.value]
    let acc = mapObjAcc(allNotes,
      (id, note) => [id, fn(now, note.timestamp, [])]) // [id, score]

    acc.sort((a, b) => b[1] - a[1]) // sort by score

    let sortedNotes = acc.map(([id, score]) => {
      let el = q(`[note-id=${id}]`)
      el.querySelector('[score]').innerText = score
      return el
    })

    q`#notes-rows`.replaceChildren(...sortedNotes)
  }

  select.replaceChildren(
    ...Object
      .keys(score_functions)
      .map(t => newElement("option", { value: t }, t))
  )
  select.value = default_score_function
  select.onchange = valueChanged
  valueChanged()
})