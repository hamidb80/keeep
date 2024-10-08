// Utils ---------------------------------------------

function toArray(smth) {
  return Array.from(smth)
}

function dedent(text) {
  // removes common indentation from `text`
  const lines = text.split('\n')

  let minIndent = Infinity
  lines.forEach(line => {
    if (line.trim().length != 0) {
      const match = line.match(/^\s*/)
      if (match && match[0].length < minIndent) {
        minIndent = match[0].length
      }
    }
  })

  // Find the minimum indentation among all lines

  return lines
    .map(line => line.substring(minIndent)) // crop after minIndent
    .join('\n')
    .trim()
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
  return Math.floor(Date.now() / 1000)
}

function toUnixTimestamp(dateObject) {
  return Math.floor(dateObject.getTime() / 1000)
}

function mapObj(obj, fn) {
  var result = {}
  for (let key in obj) {
    let val = obj[key]
    result[key] = fn(val)
  }
  return result
}

function filterObj(obj, fn) {
  var result = {}
  for (let key in obj) {
    let val = obj[key]
    if (fn(key, val))
      result[key] = val
  }
  return result
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
  el.innerHTML = inner
  return el
}

function insertAtCurrPos(el, text) {
  let pos = el.selectionStart
  let prev = el.value.substring(0, pos)
  let next = el.value.substring(pos, el.value.length)

  el.value = prev + text + ' \n' + next
}

function downloadFile(name, mime, content) {
  let a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([content], { type: mime }))
  a.download = name
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
}

function genDebounce(proc, delay) {
  let timer
  return (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => proc(...args), delay)
  }
}

function getQueryParams() {
  return Object.fromEntries(
    new URLSearchParams(window.location.search).entries())
}

function replaceQueryParams(qparams) {
  let search = new URLSearchParams(qparams)
  return window.history.pushState({}, {}, "?" + search.toString())
}

// DataBase -------------------------------------------

// ----- low level

function clearDB() {
  window.localStorage.clear()
}

function missingItemDB(key) {
  return window.localStorage.getItem(key) === null
}
function existsItemDB(key) {
  return !missingItemDB(key)
}

function getItemDB(key) {
  return JSON.parse(window.localStorage.getItem(key))
}
function setItemDB(key, val) {
  return window.localStorage.setItem(key, JSON.stringify(val))
}

function getAllItemsDB() {
  let result = {}
  for (let i = 0; i < window.localStorage.length; i++) {
    let key = window.localStorage.key(i)
    let valueStr = window.localStorage.getItem(key)
    result[key] = JSON.parse(valueStr)
  }
  return result
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
  setItemDB(noteId, history)

  return history
}

function findNoteItemEl(id) {
  return q(`[note-id='${id}']`)
}

// Actions --------------------------------------------

// Globals ---------------------------------------------

// upn : Url Param Name

const debouceDelay = 600
const scoreFunctions = {
  'creation date': (now, created, note, history) => created,
  'passed time': (now, created, note, history) => now - created,
  'history len': (now, created, note, history) => history.length,
}


var allNotes = {}
var currentNoteId = null
var current_score_function = 'creation date'

var lastTextInputValue = ''
var lastTagQueryValue = ''

// Events ----------------------------------------------

function tagQueryExprMatchesNote(tq, note) {
  let tag = tq[0].substring(1)
  let op = tq[1] ?? '?'
  let val = tq[2] ?? ''


  if (op == '?')
    return note.hashtags.some(ht => ht.name == tag)
  if (op == '!')
    return !note.hashtags.some(ht => ht.name == tag)
  if (op == '<')
    return note.hashtags.some(ht => ht.name == tag && ht.value < val)
  if (op == '<=')
    return note.hashtags.some(ht => ht.name == tag && ht.value <= val)
  if (op == '==' || op == '=')
    return note.hashtags.some(ht => ht.name == tag && ht.value == val)
  if (op == '!=')
    return note.hashtags.some(ht => ht.name == tag && ht.value != val)
  if (op == '>=')
    return note.hashtags.some(ht => ht.name == tag && ht.value >= val)
  if (op == '>')
    return note.hashtags.some(ht => ht.name == tag && ht.value > val)
}

function searchNotes(text, tagQuery) {
  let exprs =
    tagQuery
      .split(/[\n,]/g)
      .map(s => s.trim())
      .filter(s => s.length != 0)
      .map(s => s.split(/\s+/g))

  for (let id in allNotes) {
    let note = allNotes[id]
    let el = findNoteItemEl(id)
    var matches = true

    if (matches && text.length != 0) {
      matches = note.title.indexOf(text) !== -1
    }
    if (matches && exprs.length != 0) {
      for (let expr of exprs) {
        matches = tagQueryExprMatchesNote(expr, note)
        if (!matches) break
      }
    }

    el.style['display'] = matches ? "" : "none"
  }
}

function searchInputs() {
  return {
    i: q`#title-search-input`,
    tq: q`#tag-query-input`
  }
}

function searchInputsValues() {
  return mapObj(searchInputs(), el => el.value.trim())
}

function searchNotesDom() {
  let ivs = searchInputsValues()
  lastTextInputValue = ivs.i
  lastTagQueryValue = ivs.tq
  searchNotes(ivs.i, ivs.tq)
}

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
    searchNotesDom()
  }
})

up.compiler('#import-db-btn', el => {
  el.onclick = () => {
    let target = newElement('input', { type: "file", accept: ".json" })
    target.click()
  }
})

up.compiler('#export-db-btn', el => {
  el.onclick = () => {
    downloadFile(
      'keep-data.json',
      'application/json',
      JSON.stringify(getAllItemsDB()))
  }
})

up.compiler('#clear-db-btn', el => {
  el.onclick = () => {
    if (confirm("Are you sure?")) {
      clearDB()
    }
  }
})

up.compiler('#read-search-queries-from-url', () => {
  let si = searchInputs()
  let qp = getQueryParams()

  si.i.value = qp.i ?? lastTextInputValue
  si.tq.value = qp.tq ?? lastTagQueryValue

  searchNotesDom()
})

up.compiler('#score-functions-input', select => {
  function valueChanged() {
    let now = unixNow()
    current_score_function = select.value
    let fn = scoreFunctions[select.value]
    let coeff = (q`#inverse-result-checkbox`.checked ? -1 : +1)
    let acc = mapObjAcc(allNotes,
      (id, note) => [id, coeff * fn(now, note.timestamp, note, getNoteReviewHistory(id))]) // [id, score]

    acc.sort((a, b) => b[1] - a[1]) // sort by score

    let sortedNotes = acc.map(([id, score]) => {
      let el = findNoteItemEl(id)
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
    .map(p => newElement('li', { 'class': 'breadcrumb-item' }, p))

  last(subs).classList.add('text-primary')

  el.replaceChildren(...subs)
  el.classList.add('py-2', 'px-3', 'rounded')
})

// '#tag-query-errors'

up.compiler('#title-search-input', el => {
  el.oninput = genDebounce(searchNotesDom, debouceDelay)
})

up.compiler('#tag-query-input', el => {
  el.oninput = genDebounce(searchNotesDom, debouceDelay)
})

up.compiler('#share-query-btn', el => {
  el.onclick = () => {
    replaceQueryParams(
      filterObj(
        searchInputsValues(),
        (_, val) => val.length != ''))
  }
})

up.compiler('latex', el => {
  let opts = {
    displayMode: el.hasAttribute("block"),
    throwOnError: false,
    macros: {}
  }
  let bdo = newElement("bdo", { "dir": "ltr" }) // to aviod conflict  with rtl languages
  let tex = el.innerHTML

  el.replaceChildren(bdo)
  katex.render(tex, bdo, opts)
})

up.compiler('kbd', el => {
  let bdo = newElement("bdo", { "dir": "ltr" }) // to aviod conflict  with rtl languages
  bdo.innerHTML = el.innerHTML
  el.replaceChildren(bdo)
})

// up.compiler('article', wrapper => {
//   for (let codeEl of wrapper.querySelectorAll('code')) {
//     let lang = codeEl.getAttribute("lang")
//     if (lang) {
//       let src = newElement("script", { src: `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/${lang}.min.js` })
//       document.head.appendChild(src)
//       console.log(src)
//     }
//   }
// })


up.compiler('pre', el => {
  el.classList.add('text-start')
})

up.compiler('code', el => {
  if (el.hasAttribute("block")) {
    el.innerHTML = dedent(el.innerHTML)
  }

  el.setAttribute('dir', 'ltr')

  if (el.hasAttribute("lang")) {
    let lang = el.getAttribute("lang")
    el.classList.add(`lang-${lang}`)
    hljs.highlightElement(el)
  }
})

var footnoteCounter = null

up.compiler('article', el => {
  footnoteCounter = 0
})

up.compiler('[footnote]', el => {
  footnoteCounter++

  let fnid = `footnote-ref-${footnoteCounter}`
  let refid = `footnote-ref-back-${footnoteCounter}`
  let fnwrapper = q`#footnotes`
  let fnEl = newElement("li", { 'class': 'footnote' })
  let replEl = newElement("a", { id: refid, href: `#${fnid}`, 'class': 'footnote-ref', digit: '' })
  let sup = newElement("sup", {}, `${footnoteCounter}`)

  replEl.appendChild(sup)
  el.outerHTML = replEl.outerHTML

  fnEl.append(newElement("a", { id: fnid, href: `#${refid}`, 'class': 'footnote-ref-back' }, "🔼"))
  let innerFnEl = newElement("div", { dir: "auto" },)
  innerFnEl.append(...toArray(el.childNodes))
  fnEl.append(innerFnEl)

  fnwrapper.appendChild(fnEl)
})

up.macro('blockquote', el => {
  el.classList.add('px-5', 'py-3', 'fst-italic', 'bg-light')
})

up.compiler('[digit]', el => {
  // convert ASCII digits to arabic ones
  el.innerHTML = el.innerHTML.replace(/\d/g, chr => "٠١٢٣٤٥٦٧٨٩"[parseInt(chr)])
})

up.compiler('[par]', el => {
  el.prepend("(")
  el.append(")")
})

up.compiler('[trim]', el => {
  el.innerHTML = el.innerHTML.trim()
})
