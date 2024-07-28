function autoheight(element) {
  // https://stackoverflow.com/questions/55811423/css-remove-scroll-bar-and-replace-with-variable-height-for-textarea-in-a-table
  element.style.height = "0px"
  element.style.height = element.scrollHeight + "px"
}