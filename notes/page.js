
up.compiler('.tags', element => {
  let tags = element
    .innerHTML
    .split(/\n+/gmi)
    .map(t => t.trim())
    .filter(t => t.length !== 0)

  let html = tags.map(t => `
    <div class="btn btn-sm btn-outline-primary">
      ${t}
    </div>  
  `).join("\n")

  element.innerHTML = html
})
