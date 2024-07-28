function q(sel) {
  // alias
  return document.querySelector(sel)
}


function debounced(fn, delay) {
  let timeoutId
  return function (...args) {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn.apply(this, args), delay)
  }
}

function autoHeight(element) {
  // https://stackoverflow.com/questions/55811423/css-remove-scroll-bar-and-replace-with-variable-height-for-textarea-in-a-table
  element.style.height = "0px"
  element.style.height = element.scrollHeight + "px"
}

function onTextAreaInput(element) {
  autoHeight(element)
  q('#md-result').innerHTML = marked.parse(element.value)
}
