// utils ---------------------------------------------

function unixToFormattedDate(unixTimestamp) {
  let dateObject = new Date(unixTimestamp * 1000) // Convert to milliseconds
  return `${dateObject.getFullYear()}-${String(dateObject.getMonth() + 1).padStart(2, '0')}-${String(dateObject.getDate()).padStart(2, '0')} ${String(dateObject.getHours()).padStart(2, '0')}:${String(dateObject.getMinutes()).padStart(2, '0')}`
}

function toUnixTimestamp(dateObject) {
  return Math.floor(dateObject.getTime() / 1000)
}

// DOM utils -------------------------------------------

function q(sel) {
  return document.querySelector(sel)
}

function insertAtCurrPos(el, text) {
  let pos = el.selectionStart
  let prev = el.value.substring(0, pos)
  let next = el.value.substring(pos, el.value.length)

  el.value = prev + text + ' \n' + next
}

// globals ---------------------------------------------

var allNotes = {}

// unpoly setup ----------------------------------------

up.macro('[smooth-link]', link => {
  link.setAttribute('up-transition', 'cross-fade')
  link.setAttribute('up-duration', '250')
  link.setAttribute('up-follow', '')
})

up.macro('[note-data]', script => {
  let i = script.getAttribute("index")
  let j = JSON.parse(script.innerHTML)
  allNotes[i] = j
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

    console.log(exprs)
  }
})