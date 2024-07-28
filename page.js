// utils --------------------------------------

function q(sel) {
  // alias
  return document.querySelector(sel)
}
function qa(sel) {
  // alias
  return document.querySelectorAll(sel)
}

function toArray(smth) {
  return Array.from(smth)
}


function setHeight(element) {
  // automatically set height in a way that cannot be scrolled
  // https://stackoverflow.com/questions/55811423/css-remove-scroll-bar-and-replace-with-variable-height-for-textarea-in-a-table

  element.style.height = "0px"
  element.style.height = element.scrollHeight + "px"
}

function onTextAreaInput(element, e) {
  setHeight(element)
}

function clsx(el, cls, cond) {
  if (cond)
    el.classList.add(cls)
  else
    el.classList.remove(cls)
}

// impl --------------------------------------------

function changeMode(papa, editMode) {
  // console.log(papa)
  let em = papa.querySelector('.edit-mode')
  let vm = papa.querySelector('.view-mode')
  let tt = em.querySelector('textarea')

  clsx(em, 'd-none', !editMode)
  clsx(vm, 'd-none', editMode)

  vm.innerHTML = marked.parse(tt.value)
}

function onTextAreaKeyup(element, event) {
  if (event.key == "Escape") {
    element.blur()
    changeMode(element.parentElement.parentElement, false)
  }
}


function goToViewMode(el) {
  changeMode(el, false)
}

function goToEditMode(el) {
  changeMode(el, true)
}

// init ---------------------------------------------

toArray(qa('textarea')).forEach(element => {
  setHeight(element)
})

toArray(qa('.card-body')).forEach(papa => {
  goToViewMode(papa)
})
